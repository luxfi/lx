# DEX FPGA PoC Makefile

.PHONY: all clean help sim test

# Detect environment
PLATFORM ?= auto
ifeq ($(PLATFORM),auto)
    ifdef AWS_FPGA_REPO_DIR
        PLATFORM = f2
    else ifneq ($(wildcard /opt/xilinx/xrt),)
        PLATFORM = alveo
    else
        PLATFORM = sim
    endif
endif

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help:
	@echo "DEX FPGA PoC Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make sim        - Run RTL simulation"
	@echo "  make f2         - Build for AWS F2"
	@echo "  make alveo      - Build for Alveo U50/U55C"
	@echo "  make test       - Run unit tests"
	@echo "  make bench      - Run benchmarks"
	@echo "  make clean      - Clean build artifacts"
	@echo ""
	@echo "Options:"
	@echo "  PLATFORM=f2|alveo|sim  - Target platform (auto-detected)"
	@echo ""
	@echo "Current platform: $(PLATFORM)"

# Simulation target
sim:
	@echo "$(YELLOW)Running RTL simulation...$(NC)"
	cd trackB_nic_inline/sim && ./run_sim.sh

# AWS F2 build
f2:
	@echo "$(YELLOW)Building for AWS F2...$(NC)"
	cd trackA_f2_compute && ../scripts/build_vitis.sh

# Alveo build
alveo:
	@echo "$(YELLOW)Building for Alveo...$(NC)"
	cd trackB_nic_inline && ../scripts/build_vivado.sh

# Run tests
test:
	@echo "$(YELLOW)Running tests...$(NC)"
	cd common/bench && ./run_tests.sh

# Run benchmarks
bench:
	@echo "$(YELLOW)Running benchmarks...$(NC)"
	cd common/bench && ./run_benchmarks.sh

# Clean
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf build*/ */build*/ */*.xclbin */*.bit */*.o
	rm -rf */.Xil */vivado*.log */vivado*.jou
	find . -name "*.log" -delete
	find . -name "*.jou" -delete
	@echo "$(GREEN)Clean complete$(NC)"

# Install dependencies
deps:
	@echo "$(YELLOW)Checking dependencies...$(NC)"
	@which vivado > /dev/null 2>&1 || echo "$(RED)Warning: Vivado not found$(NC)"
	@which vitis > /dev/null 2>&1 || echo "$(RED)Warning: Vitis not found$(NC)"
	@which xsim > /dev/null 2>&1 || echo "$(RED)Warning: XSim not found$(NC)"
	@echo "$(GREEN)Dependency check complete$(NC)"

# Quick build (simulation only)
quick: sim test
	@echo "$(GREEN)Quick build complete$(NC)"

# Full build (all platforms)
all: sim test f2 alveo bench
	@echo "$(GREEN)Full build complete$(NC)"

# Generate documentation
docs:
	@echo "$(YELLOW)Generating documentation...$(NC)"
	cd docs && make html
	@echo "$(GREEN)Documentation at docs/_build/html/index.html$(NC)"

# Format code
fmt:
	@echo "$(YELLOW)Formatting code...$(NC)"
	find . -name "*.cpp" -o -name "*.hpp" | xargs clang-format -i
	find . -name "*.sv" -o -name "*.v" | xargs verible-verilog-format -i
	@echo "$(GREEN)Format complete$(NC)"

# Lint code
lint:
	@echo "$(YELLOW)Linting code...$(NC)"
	find . -name "*.sv" -o -name "*.v" | xargs verible-verilog-lint
	find . -name "*.cpp" -o -name "*.hpp" | xargs clang-tidy
	@echo "$(GREEN)Lint complete$(NC)"

# Package for deployment
package:
	@echo "$(YELLOW)Creating deployment package...$(NC)"
	tar -czf dex-fpga-poc-$(shell date +%Y%m%d).tar.gz \
		--exclude=build* --exclude=*.log --exclude=*.jou \
		--exclude=.git --exclude=*.xclbin --exclude=*.bit \
		.
	@echo "$(GREEN)Package created$(NC)"

.DEFAULT_GOAL := help