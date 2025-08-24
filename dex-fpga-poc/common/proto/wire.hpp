#ifndef DEX_FPGA_WIRE_HPP
#define DEX_FPGA_WIRE_HPP

#include <cstdint>

namespace dex {

// Fixed-size binary wire protocol for FPGA processing
// All multi-byte fields are little-endian
// Structures are packed with no padding

#pragma pack(push, 1)

// Order message - 48 bytes
struct OrderMsg {
    uint64_t ts_client_ns;   // Client send timestamp (nanoseconds)
    uint32_t account_id;     // Account identifier
    uint32_t symbol_id;      // Symbol identifier (0-65535 supported)
    uint64_t order_id;       // Unique order identifier
    int32_t  price_ticks;    // Price in fixed-point ticks
    int32_t  qty;            // Quantity (signed for reduce)
    uint8_t  side;           // 0=bid, 1=ask
    uint8_t  tif;            // Time-in-force: 0=GTC, 1=IOC, 2=FOK
    uint16_t flags;          // Bit flags (self-trade-prevent, post-only, etc)
    
    // Flag bits
    static constexpr uint16_t FLAG_SELF_TRADE_PREVENT = 0x0001;
    static constexpr uint16_t FLAG_POST_ONLY = 0x0002;
    static constexpr uint16_t FLAG_REDUCE_ONLY = 0x0004;
    static constexpr uint16_t FLAG_RISK_BYPASS = 0x0008;  // Internal only
};

static_assert(sizeof(OrderMsg) == 48, "OrderMsg must be 48 bytes");

// Acknowledgment/Fill message - 32 bytes
struct AckFillMsg {
    uint64_t ts_fpga_in_ns;   // FPGA ingress timestamp
    uint64_t ts_fpga_out_ns;  // FPGA egress timestamp
    uint64_t order_id;        // Original order ID
    int32_t  fill_qty;        // Filled quantity (0 for pure ACK)
    int32_t  avg_px_ticks;    // Average fill price in ticks
    
    // Helpers
    bool is_ack() const { return fill_qty == 0; }
    bool is_fill() const { return fill_qty != 0; }
};

static_assert(sizeof(AckFillMsg) == 32, "AckFillMsg must be 32 bytes");

// Cancel message - 24 bytes
struct CancelMsg {
    uint64_t ts_client_ns;   // Client send timestamp
    uint64_t order_id;       // Order to cancel
    uint32_t account_id;     // For validation
    uint32_t _reserved;      // Padding to 24 bytes
};

static_assert(sizeof(CancelMsg) == 24, "CancelMsg must be 24 bytes");

// Market data update - 40 bytes
struct MarketDataMsg {
    uint64_t ts_exchange_ns;  // Exchange timestamp
    uint32_t symbol_id;       // Symbol
    int32_t  bid_px_ticks;    // Best bid price
    int32_t  bid_qty;         // Best bid quantity
    int32_t  ask_px_ticks;    // Best ask price
    int32_t  ask_qty;         // Best ask quantity
    int32_t  last_px_ticks;   // Last trade price
    int32_t  last_qty;        // Last trade quantity
};

static_assert(sizeof(MarketDataMsg) == 40, "MarketDataMsg must be 40 bytes");

// Risk limits update - 32 bytes
struct RiskLimitsMsg {
    uint32_t account_id;      // Account to update
    uint32_t symbol_id;       // Symbol (0xFFFFFFFF for account-wide)
    int64_t  max_position;    // Maximum position size
    int64_t  max_notional;    // Maximum notional value
    uint32_t max_order_rate;  // Max orders per second
    uint32_t _reserved;       // Padding
};

static_assert(sizeof(RiskLimitsMsg) == 32, "RiskLimitsMsg must be 32 bytes");

#pragma pack(pop)

// Message type discriminator (first byte of UDP payload)
enum class MsgType : uint8_t {
    ORDER = 0x01,
    CANCEL = 0x02,
    ACK_FILL = 0x03,
    MARKET_DATA = 0x04,
    RISK_LIMITS = 0x05,
    HEARTBEAT = 0x06,
    // Add more as needed
};

// Wrapper for typed messages
struct WireMessage {
    MsgType type;
    union {
        OrderMsg order;
        CancelMsg cancel;
        AckFillMsg ack_fill;
        MarketDataMsg market_data;
        RiskLimitsMsg risk_limits;
    } payload;
};

// Fixed-point conversion helpers
inline int32_t price_to_ticks(double price, int tick_size_cents = 1) {
    return static_cast<int32_t>(price * 100.0 / tick_size_cents);
}

inline double ticks_to_price(int32_t ticks, int tick_size_cents = 1) {
    return static_cast<double>(ticks * tick_size_cents) / 100.0;
}

} // namespace dex

#endif // DEX_FPGA_WIRE_HPP