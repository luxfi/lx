#!/bin/bash
#
# Build script for on-premise NIC-resident FPGA
# Supports AMD Alveo U50/U55C cards
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  DEX FPGA PoC - NIC Build Script      ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check for Vivado installation
if [ -z "$XILINX_VIVADO" ]; then
    echo -e "${RED}Error: Vivado not found. Please source Vivado settings${NC}"
    echo "Run: source /tools/Xilinx/Vivado/2023.2/settings64.sh"
    exit 1
fi

# Detect FPGA card
echo -e "${YELLOW}Detecting FPGA cards...${NC}"
xbutil examine

# Project paths
PROJECT_ROOT=$(dirname $(dirname $(realpath $0)))
RTL_DIR=$PROJECT_ROOT/trackB_nic_inline/rtl
SIM_DIR=$PROJECT_ROOT/trackB_nic_inline/sim
BUILD_DIR=$PROJECT_ROOT/build_nic
IP_DIR=$BUILD_DIR/ip

# Create build directory
mkdir -p $BUILD_DIR
mkdir -p $IP_DIR
cd $BUILD_DIR

# Step 1: Create Vivado project
echo -e "${YELLOW}Step 1: Creating Vivado project...${NC}"
cat > create_project.tcl << 'EOF'
# Create project for Alveo U50/U55C
set proj_name "dex_fpga_nic"
set proj_dir "./vivado_project"
set part_u50 "xcu50-fsvh2104-2L-e"
set part_u55c "xcu55c-fsvh2892-2L-e"

# Try U55C first, fallback to U50
if {[catch {create_project $proj_name $proj_dir -part $part_u55c} result]} {
    puts "U55C not found, trying U50..."
    create_project $proj_name $proj_dir -part $part_u50
}

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Add RTL sources
add_files -fileset sources_1 RTL_DIR_PLACEHOLDER/*.sv
add_files -fileset sources_1 RTL_DIR_PLACEHOLDER/*.v

# Add simulation sources
add_files -fileset sim_1 SIM_DIR_PLACEHOLDER/*.sv

# Add constraints
create_fileset -constrset constrs_1
add_files -fileset constrs_1 RTL_DIR_PLACEHOLDER/../xdc/*.xdc

# Configure synthesis
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY full [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]

# Configure implementation
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

puts "Project created successfully"
EOF

sed -i "s|RTL_DIR_PLACEHOLDER|$RTL_DIR|g" create_project.tcl
sed -i "s|SIM_DIR_PLACEHOLDER|$SIM_DIR|g" create_project.tcl

vivado -mode batch -source create_project.tcl

echo -e "${GREEN}✓ Vivado project created${NC}"

# Step 2: Generate IP cores
echo -e "${YELLOW}Step 2: Generating IP cores...${NC}"
cat > generate_ip.tcl << 'EOF'
# Open project
open_project ./vivado_project/dex_fpga_nic.xpr

# Create IP directory
set ip_dir "./ip"
file mkdir $ip_dir

# 1. 100G Ethernet Subsystem
create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.1 \
    -module_name cmac_100g -dir $ip_dir
set_property -dict [list \
    CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y0} \
    CONFIG.NUM_LANES {4} \
    CONFIG.GT_REF_CLK_FREQ {161.1328125} \
    CONFIG.USER_INTERFACE {AXIS} \
    CONFIG.GT_DRP_CLK {125} \
    CONFIG.TX_FLOW_CONTROL {0} \
    CONFIG.RX_FLOW_CONTROL {0} \
    CONFIG.ENABLE_AXI_INTERFACE {1} \
    CONFIG.ENABLE_PIPELINE_REG {1} \
] [get_ips cmac_100g]

# 2. HBM Controller
create_ip -name hbm -vendor xilinx.com -library ip -version 1.0 \
    -module_name hbm_ctrl -dir $ip_dir
set_property -dict [list \
    CONFIG.USER_HBM_STACK {1} \
    CONFIG.USER_MEMORY_DISPLAY {8192} \
    CONFIG.USER_MC_ENABLE_00 {TRUE} \
    CONFIG.USER_MC_ENABLE_01 {TRUE} \
    CONFIG.USER_AXI_CLK_FREQ {250} \
] [get_ips hbm_ctrl]

# 3. System Clock MMCM
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
    -module_name sys_clk_mmcm -dir $ip_dir
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {250.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {390.625} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {156.250} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
] [get_ips sys_clk_mmcm]

# 4. AXI Interconnect for HBM
create_ip -name axi_interconnect -vendor xilinx.com -library ip -version 2.1 \
    -module_name axi_interconnect_hbm -dir $ip_dir

# Generate all IP
generate_target all [get_ips]

puts "IP cores generated successfully"
close_project
EOF

vivado -mode batch -source generate_ip.tcl

echo -e "${GREEN}✓ IP cores generated${NC}"

# Step 3: Run synthesis
echo -e "${YELLOW}Step 3: Running synthesis...${NC}"
cat > run_synthesis.tcl << 'EOF'
open_project ./vivado_project/dex_fpga_nic.xpr
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis results
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed"
}

# Report utilization
open_run synth_1
report_utilization -file synth_utilization.rpt
report_timing_summary -file synth_timing.rpt

close_project
EOF

vivado -mode batch -source run_synthesis.tcl

echo -e "${GREEN}✓ Synthesis complete${NC}"

# Step 4: Run implementation
echo -e "${YELLOW}Step 4: Running implementation...${NC}"
cat > run_implementation.tcl << 'EOF'
open_project ./vivado_project/dex_fpga_nic.xpr
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Check implementation results
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed"
}

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Reports
open_run impl_1
report_utilization -file impl_utilization.rpt
report_timing_summary -file impl_timing.rpt
report_power -file impl_power.rpt

close_project
EOF

vivado -mode batch -source run_implementation.tcl

echo -e "${GREEN}✓ Implementation and bitstream generation complete${NC}"

# Step 5: Create deployment package
echo -e "${YELLOW}Step 5: Creating deployment package...${NC}"
BITSTREAM=$(find vivado_project -name "*.bit" | head -1)
cp $BITSTREAM dex_fpga_nic.bit

# Create XRT metadata
cat > dex_fpga_nic.xclbin.info << 'EOF'
{
    "version": "1.0",
    "kernels": [{
        "name": "nic_top",
        "type": "rtl",
        "frequency": 250000000
    }],
    "interfaces": [{
        "name": "100GbE",
        "type": "network",
        "speed": 100000
    }]
}
EOF

# Create host loader script
cat > load_fpga.sh << 'EOF'
#!/bin/bash
# Load bitstream to Alveo card

BITSTREAM="dex_fpga_nic.bit"
DEVICE_ID=$(xbutil examine | grep -E "Device.*\[" | head -1 | sed 's/.*\[\(.*\)\].*/\1/')

if [ -z "$DEVICE_ID" ]; then
    echo "Error: No Alveo card detected"
    exit 1
fi

echo "Programming device: $DEVICE_ID"
xbutil program -d $DEVICE_ID -p $BITSTREAM

echo "Verifying..."
xbutil examine -d $DEVICE_ID

echo "FPGA programmed successfully"
EOF

chmod +x load_fpga.sh

# Generate test script
cat > test_loopback.sh << 'EOF'
#!/bin/bash
# Simple loopback test

# Enable 100G loopback
echo "Setting up 100G loopback test..."
devmem2 0x8000000000 w 0x1  # Enable loopback

# Send test packets
./packet_gen --rate 100g --count 1000000

# Check counters
echo "RX packets: $(devmem2 0x8000001000)"
echo "TX packets: $(devmem2 0x8000001008)"
echo "Errors: $(devmem2 0x8000001010)"
EOF

chmod +x test_loopback.sh

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}         Build Complete!                ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Generated files:"
echo "  - dex_fpga_nic.bit    : FPGA bitstream"
echo "  - load_fpga.sh        : Bitstream loader"
echo "  - test_loopback.sh    : Loopback test"
echo ""
echo "Utilization report: impl_utilization.rpt"
echo "Timing report: impl_timing.rpt"
echo ""
echo "To program FPGA:"
echo "  sudo ./load_fpga.sh"
echo ""
echo "To run loopback test:"
echo "  sudo ./test_loopback.sh"