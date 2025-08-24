#!/bin/bash
#
# Build script for AWS F2 using Vitis
# Generates XCLBIN for F2 deployment
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   DEX FPGA PoC - AWS F2 Build Script  ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running on AWS F2 Developer AMI
if [ ! -f "/opt/Xilinx/Vitis/2021.2/settings64.sh" ]; then
    echo -e "${RED}Error: Vitis not found. Please run on AWS FPGA Developer AMI${NC}"
    echo "Launch an EC2 instance with FPGA Developer AMI 1.12.2"
    exit 1
fi

# Source Vitis environment
echo -e "${YELLOW}Setting up Vitis environment...${NC}"
source /opt/Xilinx/Vitis/2021.2/settings64.sh
source /opt/xilinx/xrt/setup.sh

# Set AWS platform
export PLATFORM=/opt/xilinx/platforms/xilinx_aws-vu9p-f1_shell-v04261818_201920_2/xilinx_aws-vu9p-f1_shell-v04261818_201920_2.xpfm

# Project paths
PROJECT_ROOT=$(dirname $(dirname $(realpath $0)))
HLS_DIR=$PROJECT_ROOT/trackA_f2_compute/hls
HOST_DIR=$PROJECT_ROOT/trackA_f2_compute/host
BUILD_DIR=$PROJECT_ROOT/build_f2

# Create build directory
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Step 1: Compile HLS kernel to XO
echo -e "${YELLOW}Step 1: Compiling HLS kernel...${NC}"
v++ -c -t hw \
    --platform $PLATFORM \
    --kernel match_core \
    --hls.clock 250000000:match_core \
    -I$PROJECT_ROOT/common/proto \
    -o match_core.xo \
    $HLS_DIR/match_core.cpp

if [ $? -ne 0 ]; then
    echo -e "${RED}HLS compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ HLS kernel compiled to match_core.xo${NC}"

# Step 2: Link XO to XCLBIN
echo -e "${YELLOW}Step 2: Linking XCLBIN (this will take 2-4 hours)...${NC}"
v++ -l -t hw \
    --platform $PLATFORM \
    --kernel match_core \
    --config $PROJECT_ROOT/trackA_f2_compute/config/link.cfg \
    --optimize 3 \
    --jobs 8 \
    -o match_core.xclbin \
    match_core.xo

if [ $? -ne 0 ]; then
    echo -e "${RED}XCLBIN linking failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ XCLBIN generated: match_core.xclbin${NC}"

# Step 3: Compile host application
echo -e "${YELLOW}Step 3: Compiling host application...${NC}"
g++ -std=c++11 \
    -I$XILINX_XRT/include \
    -I$XILINX_VIVADO/include \
    -I$PROJECT_ROOT/common/proto \
    -L$XILINX_XRT/lib \
    -lOpenCL -lpthread -lrt \
    -o dex_fpga_host \
    $HOST_DIR/main.cpp \
    $HOST_DIR/fpga_manager.cpp

if [ $? -ne 0 ]; then
    echo -e "${RED}Host compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Host application compiled: dex_fpga_host${NC}"

# Step 4: Create AFI (Amazon FPGA Image)
echo -e "${YELLOW}Step 4: Creating AFI for F2 deployment...${NC}"
$XILINX_SDX/tools/create_sdaccel_afi.sh \
    -xclbin=match_core.xclbin \
    -o=match_core \
    -s3_bucket=your-s3-bucket \
    -s3_dcp_key=dcp \
    -s3_logs_key=logs

# Parse AFI ID from output
AFI_ID=$(grep "afi-" *afi_id.txt | cut -d' ' -f2)
echo -e "${GREEN}✓ AFI created: $AFI_ID${NC}"

# Step 5: Wait for AFI to be available
echo -e "${YELLOW}Step 5: Waiting for AFI to become available...${NC}"
aws ec2 describe-fpga-images --fpga-image-ids $AFI_ID

# Step 6: Generate run script
cat > run_f2.sh << 'EOF'
#!/bin/bash
# Load AFI and run application

# Check FPGA status
sudo fpga-describe-local-image -S 0

# Clear any existing AFI
sudo fpga-clear-local-image -S 0

# Load new AFI
sudo fpga-load-local-image -S 0 -I AFI_ID_PLACEHOLDER

# Wait for load
sleep 5

# Verify load
sudo fpga-describe-local-image -S 0

# Run application
sudo ./dex_fpga_host match_core.xclbin
EOF

sed -i "s/AFI_ID_PLACEHOLDER/$AFI_ID/g" run_f2.sh
chmod +x run_f2.sh

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}         Build Complete!                ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Generated files:"
echo "  - match_core.xo       : HLS kernel object"
echo "  - match_core.xclbin   : FPGA binary"
echo "  - dex_fpga_host       : Host application"
echo "  - AFI ID              : $AFI_ID"
echo ""
echo "To run on F2 instance:"
echo "  ./run_f2.sh"
echo ""
echo -e "${YELLOW}Note: AFI creation takes 30-60 minutes${NC}"
echo -e "${YELLOW}Check status: aws ec2 describe-fpga-images --fpga-image-ids $AFI_ID${NC}"