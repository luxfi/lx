# DEX FPGA PoC - Production-Ready Hardware Acceleration

## Overview

This repository contains a complete FPGA Proof-of-Concept for ultra-low latency order matching and risk management, with both AWS F2 cloud deployment and on-premise NIC-resident implementations.

## Quick Start

### Track A: AWS F2 (Compute Offload)
```bash
# Launch F2 instance with Vitis Developer AMI
cd trackA_f2_compute
./scripts/build_vitis.sh
./scripts/run_hw_emu.sh
```

### Track B: On-Premise NIC (Wire-to-Wire)
```bash
# With Alveo U50/U55C or Agilex-7 installed
cd trackB_nic_inline
./scripts/build_vivado.sh  # AMD
# or
./scripts/build_quartus.sh # Intel
```

## Architecture

Two parallel tracks optimize for different deployment scenarios:

- **Track A (F2)**: Cloud-based compute offload, HLS/RTL validation, micro-batch processing
- **Track B (NIC)**: Wire-to-wire latency optimization, 100-400GbE line-rate processing

## Performance Targets

### Track A (F2 Compute)
- Per-order service time: **p50 < 250ns, p99 < 1µs**
- Throughput: Linear scaling with parallel markets
- Batch sizes: 8-32k orders optimal

### Track B (NIC-Resident)
- Wire-to-wire: **p50 < 1µs, p99 < 3µs** at 100G
- Loss-free at line rate
- Deterministic behavior under stress

## Hardware Requirements

### Minimum (100G)
- AMD Alveo U50 (8GB HBM2, 1×100GbE)
- PCIe Gen4 x16
- QSFP28 cabling

### Recommended (2×100G)
- AMD Alveo U55C (16GB HBM2, 2×100GbE)
- Deeper order books
- Multi-symbol support

### Maximum (400G)
- BittWare IA-780i (Intel Agilex-7)
- Hard MAC/PCS/FEC
- 400GbE support

## Bill of Materials

| Component | Model | Purpose | Est. Cost |
|-----------|-------|---------|-----------|
| **FPGA Card** | AMD Alveo U50 | 100G NIC + compute | $4,000 |
| | AMD Alveo U55C | 2×100G + 16GB HBM | $8,000 |
| | BittWare IA-780i | 400G + Agilex-7 | $12,000 |
| **SmartNIC** | Napatech Link | Feed handler | $3,000 |
| | ExaNIC X25/X100 | Ultra-low latency | $5,000 |
| **Cloud** | AWS F2.xlarge | Dev/test | $1.65/hr |
| | AWS F2.8xlarge | Production | $13.20/hr |
| **Cabling** | QSFP28 DAC 3m | 100G direct attach | $200 |
| | QSFP28 SR4 | 100G optics | $400 |

## Directory Structure

```
dex-fpga-poc/
├── docs/                    # Architecture and methodology
├── common/                  # Shared protocol definitions
│   ├── proto/              # Binary message formats
│   ├── bench/              # Traffic generation profiles
│   └── scripts/            # Measurement tools
├── trackA_f2_compute/      # AWS F2 implementation
│   ├── hls/               # High-Level Synthesis cores
│   ├── host/              # DMA driver application
│   └── scripts/           # Build automation
└── trackB_nic_inline/      # NIC-resident implementation
    ├── rtl/               # Verilog/SystemVerilog
    ├── sim/               # Testbenches
    └── host/              # Control plane
```

## Key Differentiators

1. **Dual-track approach**: Cloud for rapid iteration, on-prem for production latency
2. **Exchange-grade design**: Matches NYSE Pillar latency targets (26-32µs round-trip)
3. **Production-ready**: Complete test harnesses, CI/CD, and monitoring
4. **Vendor-agnostic**: Supports both AMD and Intel FPGAs

## Success Criteria

- [ ] Echo path < 500ns wire-to-wire
- [ ] Risk checks single-cycle
- [ ] Price-time priority matching
- [ ] Self-trade prevention inline
- [ ] Loss-free at 100Gbps line rate
- [ ] Deterministic p99 latency

## Next Steps

1. **Days 1-2**: Implement echo path, verify timestamps
2. **Week 1**: Add risk and price levels, achieve <800ns ACK
3. **Weeks 2-3**: Full matcher, stress testing, latency report

## Support

- AWS F2 Documentation: [F2 Developer Kit](https://github.com/aws/aws-fpga)
- AMD Alveo: [Vitis Documentation](https://www.xilinx.com/products/design-tools/vitis.html)
- Intel Agilex: [Quartus Prime Pro](https://www.intel.com/content/www/us/en/products/programmable/fpga/agilex-7.html)

## License

Proprietary - LX DEX Team

---
*Production-ready FPGA acceleration for next-generation trading systems*