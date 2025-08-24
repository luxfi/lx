/**
 * NIC-Resident Order Processing Pipeline
 * 
 * Wire-to-wire ultra-low latency implementation for
 * AMD Alveo U50/U55C or Intel Agilex-7 with 100GbE
 */

module nic_top #(
    parameter ENABLE_100G = 1,
    parameter ENABLE_PTP = 1,
    parameter NUM_SYMBOLS = 256,
    parameter BOOK_DEPTH = 32
)(
    // Clock and reset
    input  logic         clk_100g,      // 100GbE clock (390.625 MHz)
    input  logic         clk_core,      // Core clock (250 MHz)
    input  logic         clk_ptp,       // PTP clock (156.25 MHz)
    input  logic         rst_n,
    
    // 100GbE MAC interface (AXI-Stream)
    input  logic [511:0] rx_axis_tdata,
    input  logic [63:0]  rx_axis_tkeep,
    input  logic         rx_axis_tvalid,
    output logic         rx_axis_tready,
    input  logic         rx_axis_tlast,
    input  logic [15:0]  rx_axis_tuser,
    
    output logic [511:0] tx_axis_tdata,
    output logic [63:0]  tx_axis_tkeep,
    output logic         tx_axis_tvalid,
    input  logic         tx_axis_tready,
    output logic         tx_axis_tlast,
    output logic [15:0]  tx_axis_tuser,
    
    // PTP timestamp interface
    input  logic [63:0]  ptp_timestamp_ns,
    input  logic         ptp_timestamp_valid,
    
    // HBM interface (AXI4)
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    
    output logic [511:0] m_axi_wdata,
    output logic [63:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,
    
    // Control/Status interface (AXI-Lite)
    input  logic [31:0]  s_axil_awaddr,
    input  logic         s_axil_awvalid,
    output logic         s_axil_awready,
    
    input  logic [31:0]  s_axil_wdata,
    input  logic [3:0]   s_axil_wstrb,
    input  logic         s_axil_wvalid,
    output logic         s_axil_wready,
    
    output logic [1:0]   s_axil_bresp,
    output logic         s_axil_bvalid,
    input  logic         s_axil_bready,
    
    // Statistics outputs
    output logic [63:0]  stat_orders_processed,
    output logic [63:0]  stat_orders_matched,
    output logic [63:0]  stat_latency_cycles,
    output logic [31:0]  stat_error_count
);

// Internal signals
logic [511:0] packet_data;
logic         packet_valid;
logic         packet_ready;
logic [15:0]  packet_len;
logic [63:0]  rx_timestamp;

// Order message decoded
logic [63:0]  order_timestamp;
logic [31:0]  order_account_id;
logic [31:0]  order_symbol_id;
logic [63:0]  order_id;
logic [31:0]  order_price;
logic [31:0]  order_qty;
logic [7:0]   order_side;
logic [7:0]   order_tif;
logic [15:0]  order_flags;
logic         order_valid;
logic         order_ready;

// Match results
logic [63:0]  match_order_id;
logic [31:0]  match_qty;
logic [31:0]  match_price;
logic [63:0]  match_timestamp_in;
logic [63:0]  match_timestamp_out;
logic         match_valid;
logic         match_ready;

// =========================================================================
// RX Path: Packet Parser
// =========================================================================
packet_parser parser_inst (
    .clk(clk_100g),
    .rst_n(rst_n),
    
    // From MAC
    .rx_tdata(rx_axis_tdata),
    .rx_tkeep(rx_axis_tkeep),
    .rx_tvalid(rx_axis_tvalid),
    .rx_tready(rx_axis_tready),
    .rx_tlast(rx_axis_tlast),
    
    // PTP timestamp
    .ptp_timestamp(ptp_timestamp_ns),
    
    // Parsed output
    .packet_data(packet_data),
    .packet_valid(packet_valid),
    .packet_ready(packet_ready),
    .packet_len(packet_len),
    .rx_timestamp(rx_timestamp)
);

// =========================================================================
// Order Decoder (Fixed 48-byte messages)
// =========================================================================
order_decoder decoder_inst (
    .clk(clk_100g),
    .rst_n(rst_n),
    
    // From parser
    .packet_data(packet_data),
    .packet_valid(packet_valid),
    .packet_ready(packet_ready),
    .rx_timestamp(rx_timestamp),
    
    // Decoded order
    .order_timestamp(order_timestamp),
    .order_account_id(order_account_id),
    .order_symbol_id(order_symbol_id),
    .order_id(order_id),
    .order_price(order_price),
    .order_qty(order_qty),
    .order_side(order_side),
    .order_tif(order_tif),
    .order_flags(order_flags),
    .order_valid(order_valid),
    .order_ready(order_ready)
);

// =========================================================================
// Risk Check Module (Single-cycle)
// =========================================================================
wire risk_pass;
wire [31:0] risk_max_position;
wire [31:0] risk_max_notional;

risk_checker risk_inst (
    .clk(clk_100g),
    .rst_n(rst_n),
    
    // Order input
    .account_id(order_account_id),
    .symbol_id(order_symbol_id),
    .price(order_price),
    .qty(order_qty),
    .side(order_side),
    
    // Risk decision (combinational)
    .risk_pass(risk_pass),
    
    // Configuration (from AXI-Lite)
    .max_position(risk_max_position),
    .max_notional(risk_max_notional)
);

// =========================================================================
// Matching Engine Core
// =========================================================================
matching_engine #(
    .NUM_SYMBOLS(NUM_SYMBOLS),
    .BOOK_DEPTH(BOOK_DEPTH)
) matcher_inst (
    .clk(clk_core),
    .rst_n(rst_n),
    
    // Order input
    .order_id(order_id),
    .symbol_id(order_symbol_id[7:0]),  // Support 256 symbols
    .price(order_price),
    .qty(order_qty),
    .side(order_side[0]),  // 0=buy, 1=sell
    .tif(order_tif[1:0]),   // 0=GTC, 1=IOC, 2=FOK
    .valid(order_valid & risk_pass),
    .ready(order_ready),
    
    // Match output
    .match_order_id(match_order_id),
    .match_qty(match_qty),
    .match_price(match_price),
    .match_timestamp_in(order_timestamp),
    .match_timestamp_out(match_timestamp_out),
    .match_valid(match_valid),
    .match_ready(match_ready),
    
    // HBM interface for book storage
    .hbm_addr(m_axi_awaddr),
    .hbm_wdata(m_axi_wdata),
    .hbm_wvalid(m_axi_wvalid),
    .hbm_wready(m_axi_wready)
);

// =========================================================================
// TX Path: Response Builder
// =========================================================================
response_builder builder_inst (
    .clk(clk_100g),
    .rst_n(rst_n),
    
    // Match input
    .match_order_id(match_order_id),
    .match_qty(match_qty),
    .match_price(match_price),
    .match_timestamp_in(match_timestamp_in),
    .match_timestamp_out(match_timestamp_out),
    .match_valid(match_valid),
    .match_ready(match_ready),
    
    // To MAC
    .tx_tdata(tx_axis_tdata),
    .tx_tkeep(tx_axis_tkeep),
    .tx_tvalid(tx_axis_tvalid),
    .tx_tready(tx_axis_tready),
    .tx_tlast(tx_axis_tlast)
);

// =========================================================================
// Statistics Collection
// =========================================================================
always_ff @(posedge clk_core) begin
    if (!rst_n) begin
        stat_orders_processed <= 64'b0;
        stat_orders_matched <= 64'b0;
        stat_latency_cycles <= 64'b0;
        stat_error_count <= 32'b0;
    end else begin
        // Count processed orders
        if (order_valid & order_ready) begin
            stat_orders_processed <= stat_orders_processed + 1;
        end
        
        // Count matched orders
        if (match_valid & match_ready & (match_qty != 0)) begin
            stat_orders_matched <= stat_orders_matched + 1;
        end
        
        // Track latency (simplified - would use histogram in production)
        if (match_valid & match_ready) begin
            stat_latency_cycles <= match_timestamp_out - match_timestamp_in;
        end
        
        // Count errors (risk failures, etc)
        if (order_valid & !risk_pass) begin
            stat_error_count <= stat_error_count + 1;
        end
    end
end

// =========================================================================
// Control Interface (AXI-Lite)
// =========================================================================
control_registers ctrl_inst (
    .clk(clk_core),
    .rst_n(rst_n),
    
    // AXI-Lite slave
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    
    // Configuration outputs
    .risk_max_position(risk_max_position),
    .risk_max_notional(risk_max_notional)
);

endmodule

// =========================================================================
// Sub-module: Packet Parser
// =========================================================================
module packet_parser (
    input  logic         clk,
    input  logic         rst_n,
    
    // MAC interface
    input  logic [511:0] rx_tdata,
    input  logic [63:0]  rx_tkeep,
    input  logic         rx_tvalid,
    output logic         rx_tready,
    input  logic         rx_tlast,
    
    // PTP timestamp
    input  logic [63:0]  ptp_timestamp,
    
    // Parsed output
    output logic [511:0] packet_data,
    output logic         packet_valid,
    input  logic         packet_ready,
    output logic [15:0]  packet_len,
    output logic [63:0]  rx_timestamp
);

// Simple pass-through for now - would parse UDP in production
always_ff @(posedge clk) begin
    if (!rst_n) begin
        packet_valid <= 1'b0;
        rx_tready <= 1'b1;
    end else begin
        rx_tready <= packet_ready;
        
        if (rx_tvalid && rx_tready) begin
            packet_data <= rx_tdata;
            packet_valid <= rx_tlast;  // Assume single-beat packets
            packet_len <= 16'd48;      // Fixed order size
            rx_timestamp <= ptp_timestamp;
        end else if (packet_ready) begin
            packet_valid <= 1'b0;
        end
    end
end

endmodule

// =========================================================================
// Sub-module: Order Decoder
// =========================================================================
module order_decoder (
    input  logic         clk,
    input  logic         rst_n,
    
    // Packet input
    input  logic [511:0] packet_data,
    input  logic         packet_valid,
    output logic         packet_ready,
    input  logic [63:0]  rx_timestamp,
    
    // Decoded order output
    output logic [63:0]  order_timestamp,
    output logic [31:0]  order_account_id,
    output logic [31:0]  order_symbol_id,
    output logic [63:0]  order_id,
    output logic [31:0]  order_price,
    output logic [31:0]  order_qty,
    output logic [7:0]   order_side,
    output logic [7:0]   order_tif,
    output logic [15:0]  order_flags,
    output logic         order_valid,
    input  logic         order_ready
);

// Decode 48-byte order message from packet
// Assuming order starts at byte 42 (after Eth+IP+UDP headers)
always_ff @(posedge clk) begin
    if (!rst_n) begin
        order_valid <= 1'b0;
        packet_ready <= 1'b1;
    end else begin
        packet_ready <= order_ready;
        
        if (packet_valid && packet_ready) begin
            // Extract fields (little-endian)
            order_timestamp  <= packet_data[335:272];  // Bytes 42-49
            order_account_id <= packet_data[271:240];  // Bytes 50-53
            order_symbol_id  <= packet_data[239:208];  // Bytes 54-57
            order_id         <= packet_data[207:144];  // Bytes 58-65
            order_price      <= packet_data[143:112];  // Bytes 66-69
            order_qty        <= packet_data[111:80];   // Bytes 70-73
            order_side       <= packet_data[79:72];    // Byte 74
            order_tif        <= packet_data[71:64];    // Byte 75
            order_flags      <= packet_data[63:48];    // Bytes 76-77
            order_valid      <= 1'b1;
        end else if (order_ready) begin
            order_valid <= 1'b0;
        end
    end
end

endmodule