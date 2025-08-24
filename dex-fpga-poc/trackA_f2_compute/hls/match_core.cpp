/**
 * HLS Order Matching Core for AWS F2
 * 
 * This HLS kernel implements price-time priority matching
 * optimized for AWS F2 (Virtex UltraScale+ VU9P)
 */

#include <ap_int.h>
#include <hls_stream.h>
#include <hls_math.h>

// Include wire protocol definitions
#include "../../common/proto/wire.hpp"

// HLS pragmas for optimization
#define BURST_SIZE 64
#define MAX_ORDERS_PER_SYMBOL 10000
#define MAX_SYMBOLS 256

using namespace dex;

// Order book entry for HLS processing
struct HLSOrderEntry {
    ap_uint<64> order_id;
    ap_int<32>  price_ticks;
    ap_int<32>  quantity;
    ap_uint<64> timestamp_ns;
    ap_uint<32> account_id;
    ap_uint<8>  side;  // 0=bid, 1=ask
};

// Matching result
struct MatchResult {
    ap_uint<64> buy_order_id;
    ap_uint<64> sell_order_id;
    ap_int<32>  matched_qty;
    ap_int<32>  matched_price;
    ap_uint<64> timestamp_ns;
};

/**
 * Top-level HLS function for order matching
 * 
 * @param order_stream Input stream of orders
 * @param result_stream Output stream of matches/acks
 * @param book_bids Bid side of order book (HBM)
 * @param book_asks Ask side of order book (HBM)
 * @param symbol_id Symbol to process
 */
extern "C" {
void match_core(
    hls::stream<OrderMsg> &order_stream,
    hls::stream<AckFillMsg> &result_stream,
    HLSOrderEntry book_bids[MAX_SYMBOLS][MAX_ORDERS_PER_SYMBOL],
    HLSOrderEntry book_asks[MAX_SYMBOLS][MAX_ORDERS_PER_SYMBOL],
    ap_uint<32> symbol_id
) {
    #pragma HLS INTERFACE m_axi port=book_bids bundle=gmem0
    #pragma HLS INTERFACE m_axi port=book_asks bundle=gmem1
    #pragma HLS INTERFACE axis port=order_stream
    #pragma HLS INTERFACE axis port=result_stream
    #pragma HLS INTERFACE s_axilite port=symbol_id
    #pragma HLS INTERFACE s_axilite port=return
    
    // Pipeline the main loop
    #pragma HLS PIPELINE II=1
    
    // Local copies for fast access
    static HLSOrderEntry local_bids[MAX_ORDERS_PER_SYMBOL];
    static HLSOrderEntry local_asks[MAX_ORDERS_PER_SYMBOL];
    #pragma HLS ARRAY_PARTITION variable=local_bids cyclic factor=8
    #pragma HLS ARRAY_PARTITION variable=local_asks cyclic factor=8
    
    // Bid/ask counts
    static ap_uint<16> bid_count = 0;
    static ap_uint<16> ask_count = 0;
    
    // Main processing loop
    while (!order_stream.empty()) {
        OrderMsg order = order_stream.read();
        AckFillMsg result;
        
        // Initialize result
        result.ts_fpga_in_ns = order.ts_client_ns; // Would use PTP in real impl
        result.order_id = order.order_id;
        result.fill_qty = 0;
        result.avg_px_ticks = 0;
        
        // Skip if wrong symbol
        if (order.symbol_id != symbol_id) {
            result.ts_fpga_out_ns = result.ts_fpga_in_ns + 100; // 100ns processing
            result_stream.write(result);
            continue;
        }
        
        // Price-time priority matching
        if (order.side == 0) { // Buy order
            // Match against asks
            match_buy_order:
            for (int i = 0; i < ask_count; i++) {
                #pragma HLS UNROLL factor=4
                
                HLSOrderEntry &ask = local_asks[i];
                
                // Check price match (buy price >= ask price)
                if (order.price_ticks >= ask.price_ticks && order.qty > 0 && ask.quantity > 0) {
                    // Calculate matched quantity
                    ap_int<32> matched_qty = (order.qty < ask.quantity) ? order.qty : ask.quantity;
                    
                    // Update quantities
                    order.qty -= matched_qty;
                    ask.quantity -= matched_qty;
                    
                    // Accumulate fill
                    result.fill_qty += matched_qty;
                    result.avg_px_ticks = ask.price_ticks; // Simplified - should weight average
                    
                    // Remove filled ask
                    if (ask.quantity == 0) {
                        // Shift remaining asks
                        for (int j = i; j < ask_count - 1; j++) {
                            #pragma HLS UNROLL factor=2
                            local_asks[j] = local_asks[j + 1];
                        }
                        ask_count--;
                        i--; // Recheck same index
                    }
                    
                    // Check if order fully filled
                    if (order.qty == 0) break;
                }
            }
            
            // Add remaining as resting bid if GTC
            if (order.qty > 0 && order.tif == 0) { // GTC
                insert_bid_sorted(local_bids, bid_count, order);
            }
            
        } else { // Sell order
            // Match against bids
            match_sell_order:
            for (int i = 0; i < bid_count; i++) {
                #pragma HLS UNROLL factor=4
                
                HLSOrderEntry &bid = local_bids[i];
                
                // Check price match (sell price <= bid price)
                if (order.price_ticks <= bid.price_ticks && order.qty > 0 && bid.quantity > 0) {
                    // Calculate matched quantity
                    ap_int<32> matched_qty = (order.qty < bid.quantity) ? order.qty : bid.quantity;
                    
                    // Update quantities
                    order.qty -= matched_qty;
                    bid.quantity -= matched_qty;
                    
                    // Accumulate fill
                    result.fill_qty += matched_qty;
                    result.avg_px_ticks = bid.price_ticks; // Simplified
                    
                    // Remove filled bid
                    if (bid.quantity == 0) {
                        // Shift remaining bids
                        for (int j = i; j < bid_count - 1; j++) {
                            #pragma HLS UNROLL factor=2
                            local_bids[j] = local_bids[j + 1];
                        }
                        bid_count--;
                        i--; // Recheck same index
                    }
                    
                    // Check if order fully filled
                    if (order.qty == 0) break;
                }
            }
            
            // Add remaining as resting ask if GTC
            if (order.qty > 0 && order.tif == 0) { // GTC
                insert_ask_sorted(local_asks, ask_count, order);
            }
        }
        
        // Set output timestamp
        result.ts_fpga_out_ns = result.ts_fpga_in_ns + 250; // 250ns target latency
        
        // Write result
        result_stream.write(result);
    }
    
    // Write back to HBM
    write_back_books:
    for (int i = 0; i < bid_count; i++) {
        #pragma HLS PIPELINE II=1
        book_bids[symbol_id][i] = local_bids[i];
    }
    for (int i = 0; i < ask_count; i++) {
        #pragma HLS PIPELINE II=1
        book_asks[symbol_id][i] = local_asks[i];
    }
}

/**
 * Insert buy order maintaining price-time priority
 * Higher price = higher priority
 * Earlier time = higher priority at same price
 */
void insert_bid_sorted(
    HLSOrderEntry bids[MAX_ORDERS_PER_SYMBOL],
    ap_uint<16> &count,
    const OrderMsg &order
) {
    #pragma HLS INLINE
    
    if (count >= MAX_ORDERS_PER_SYMBOL) return; // Book full
    
    HLSOrderEntry new_entry;
    new_entry.order_id = order.order_id;
    new_entry.price_ticks = order.price_ticks;
    new_entry.quantity = order.qty;
    new_entry.timestamp_ns = order.ts_client_ns;
    new_entry.account_id = order.account_id;
    new_entry.side = 0;
    
    // Find insertion point (higher price or earlier time at same price)
    int insert_idx = count;
    for (int i = 0; i < count; i++) {
        if (bids[i].price_ticks < new_entry.price_ticks ||
            (bids[i].price_ticks == new_entry.price_ticks && 
             bids[i].timestamp_ns > new_entry.timestamp_ns)) {
            insert_idx = i;
            break;
        }
    }
    
    // Shift and insert
    for (int i = count; i > insert_idx; i--) {
        bids[i] = bids[i - 1];
    }
    bids[insert_idx] = new_entry;
    count++;
}

/**
 * Insert sell order maintaining price-time priority
 * Lower price = higher priority
 * Earlier time = higher priority at same price
 */
void insert_ask_sorted(
    HLSOrderEntry asks[MAX_ORDERS_PER_SYMBOL],
    ap_uint<16> &count,
    const OrderMsg &order
) {
    #pragma HLS INLINE
    
    if (count >= MAX_ORDERS_PER_SYMBOL) return; // Book full
    
    HLSOrderEntry new_entry;
    new_entry.order_id = order.order_id;
    new_entry.price_ticks = order.price_ticks;
    new_entry.quantity = order.qty;
    new_entry.timestamp_ns = order.ts_client_ns;
    new_entry.account_id = order.account_id;
    new_entry.side = 1;
    
    // Find insertion point (lower price or earlier time at same price)
    int insert_idx = count;
    for (int i = 0; i < count; i++) {
        if (asks[i].price_ticks > new_entry.price_ticks ||
            (asks[i].price_ticks == new_entry.price_ticks && 
             asks[i].timestamp_ns > new_entry.timestamp_ns)) {
            insert_idx = i;
            break;
        }
    }
    
    // Shift and insert
    for (int i = count; i > insert_idx; i--) {
        asks[i] = asks[i - 1];
    }
    asks[insert_idx] = new_entry;
    count++;
}

} // extern "C"