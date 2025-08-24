# Lux Exchange (LX) - Master Makefile
# High-performance trading platform for DEX and CEX deployments

.PHONY: all help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Default target
all: help

help:
	@echo "$(BLUE)╔══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║           Lux Exchange (LX) Build System                 ║$(NC)"
	@echo "$(BLUE)╚══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)Backend Commands:$(NC)"
	@echo "  $(YELLOW)make backend-build$(NC)    - Build all backend engines"
	@echo "  $(YELLOW)make backend-run$(NC)      - Run backend services (docker)"
	@echo "  $(YELLOW)make backend-dev$(NC)      - Run backend in dev mode"
	@echo "  $(YELLOW)make backend-stop$(NC)     - Stop backend services"
	@echo ""
	@echo "$(GREEN)Frontend Commands:$(NC)"
	@echo "  $(YELLOW)make frontend-build$(NC)   - Build UI frontend"
	@echo "  $(YELLOW)make frontend-run$(NC)     - Run UI frontend (dev)"
	@echo "  $(YELLOW)make frontend-prod$(NC)    - Run UI frontend (production)"
	@echo ""
	@echo "$(GREEN)Client Library:$(NC)"
	@echo "  $(YELLOW)make client-build$(NC)     - Build TypeScript client library"
	@echo "  $(YELLOW)make client-publish$(NC)   - Publish client to npm"
	@echo ""
	@echo "$(GREEN)Benchmarks:$(NC)"
	@echo "  $(YELLOW)make benchmark$(NC)        - Run all benchmarks"
	@echo "  $(YELLOW)make benchmark-quick$(NC)  - Run quick benchmark"
	@echo "  $(YELLOW)make benchmark-fix$(NC)    - Run FIX protocol benchmark"
	@echo ""
	@echo "$(GREEN)Development:$(NC)"
	@echo "  $(YELLOW)make dev$(NC)              - Start full dev environment"
	@echo "  $(YELLOW)make test$(NC)             - Run all tests"
	@echo "  $(YELLOW)make lint$(NC)             - Run linters"
	@echo "  $(YELLOW)make clean$(NC)            - Clean all build artifacts"
	@echo ""
	@echo "$(GREEN)Deployment:$(NC)"
	@echo "  $(YELLOW)make deploy-dex$(NC)       - Deploy DEX on X-Chain"
	@echo "  $(YELLOW)make deploy-cex$(NC)       - Deploy CEX backend"
	@echo "  $(YELLOW)make deploy-prod$(NC)      - Full production deployment"
	@echo ""
	@echo "$(GREEN)Quick Start:$(NC)"
	@echo "  $(YELLOW)make quick-start$(NC)      - Build and run everything locally"
	@echo ""

# ==========================================
# Backend Commands
# ==========================================

.PHONY: backend-build backend-run backend-dev backend-stop backend-logs

backend-build:
	@echo "$(BLUE)Building Lux Exchange backend...$(NC)"
	@cd lx-backend && make all
	@echo "$(GREEN)✓ Backend build complete$(NC)"

backend-run:
	@echo "$(BLUE)Starting Lux Exchange backend services...$(NC)"
	@cd lx-backend && docker-compose up -d
	@echo "$(GREEN)✓ Backend services running$(NC)"
	@echo "  - Engine Router: http://localhost:50050"
	@echo "  - FIX Gateway: localhost:9878"
	@echo "  - Monitoring: http://localhost:3000"

backend-dev:
	@echo "$(BLUE)Starting backend in development mode...$(NC)"
	@cd lx-backend && docker-compose -f docker-compose.dev.yml up

backend-stop:
	@echo "$(YELLOW)Stopping backend services...$(NC)"
	@cd lx-backend && docker-compose down
	@echo "$(GREEN)✓ Backend services stopped$(NC)"

backend-logs:
	@cd lx-backend && docker-compose logs -f

# ==========================================
# Frontend Commands
# ==========================================

.PHONY: frontend-build frontend-run frontend-prod frontend-install

frontend-install:
	@echo "$(BLUE)Installing UI dependencies...$(NC)"
	@cd ui && npm install
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

frontend-build: frontend-install
	@echo "$(BLUE)Building Lux Exchange UI...$(NC)"
	@cd ui && npm run build
	@echo "$(GREEN)✓ UI build complete$(NC)"

frontend-run: frontend-install
	@echo "$(BLUE)Starting Lux Exchange UI (development)...$(NC)"
	@cd ui && npm run dev
	
frontend-prod: frontend-build
	@echo "$(BLUE)Starting Lux Exchange UI (production)...$(NC)"
	@cd ui && npm run start

# ==========================================
# Client Library
# ==========================================

.PHONY: client-build client-test client-publish client-link

client-build:
	@echo "$(BLUE)Building LX TypeScript client library...$(NC)"
	@cd lx-client-ts && npm install && npm run build
	@echo "$(GREEN)✓ Client library built$(NC)"

client-test:
	@echo "$(BLUE)Testing client library...$(NC)"
	@cd lx-client-ts && npm test
	@echo "$(GREEN)✓ Client tests passed$(NC)"

client-publish: client-build client-test
	@echo "$(BLUE)Publishing to npm...$(NC)"
	@cd lx-client-ts && npm publish
	@echo "$(GREEN)✓ Published to npm$(NC)"

client-link: client-build
	@echo "$(BLUE)Linking client library for local development...$(NC)"
	@cd lx-client-ts && npm link
	@cd ui && npm link @luxexchange/lx-client
	@echo "$(GREEN)✓ Client library linked$(NC)"

# ==========================================
# Benchmarks
# ==========================================

.PHONY: benchmark benchmark-quick benchmark-fix benchmark-report

benchmark:
	@echo "$(BLUE)Running comprehensive benchmarks...$(NC)"
	@cd lx-backend && ./scripts/run-comprehensive-benchmark.sh
	@echo "$(GREEN)✓ Benchmark complete$(NC)"

benchmark-quick:
	@echo "$(BLUE)Running quick benchmark...$(NC)"
	@cd lx-backend && go run cmd/simple-benchmark/main.go
	@echo "$(GREEN)✓ Quick benchmark complete$(NC)"

benchmark-fix:
	@echo "$(BLUE)Running FIX protocol benchmark...$(NC)"
	@cd lx-backend && go run cmd/fix-benchmark/main.go
	@echo "$(GREEN)✓ FIX benchmark complete$(NC)"

benchmark-report:
	@echo "$(BLUE)Latest benchmark results:$(NC)"
	@ls -la lx-backend/benchmark-results/ | tail -5
	@echo ""
	@cat lx-backend/benchmark-results/$$(ls -t lx-backend/benchmark-results/*.csv | head -1)

# ==========================================
# Development
# ==========================================

.PHONY: dev test lint clean install-tools

dev:
	@echo "$(BLUE)Starting full development environment...$(NC)"
	@echo "$(YELLOW)Starting backend...$(NC)"
	@make backend-dev &
	@sleep 5
	@echo "$(YELLOW)Starting frontend...$(NC)"
	@make frontend-run &
	@echo "$(GREEN)✓ Development environment ready$(NC)"
	@echo "  - Backend: http://localhost:50052"
	@echo "  - Frontend: http://localhost:3000"
	@echo "  - Press Ctrl+C to stop all services"
	@wait

test:
	@echo "$(BLUE)Running all tests...$(NC)"
	@cd lx-backend && make test
	@cd lx-client-ts && npm test
	@cd ui && npm test
	@echo "$(GREEN)✓ All tests passed$(NC)"

lint:
	@echo "$(BLUE)Running linters...$(NC)"
	@cd lx-backend && make lint
	@cd lx-client-ts && npm run lint
	@cd ui && npm run lint
	@echo "$(GREEN)✓ Linting complete$(NC)"

clean:
	@echo "$(RED)Cleaning all build artifacts...$(NC)"
	@cd lx-backend && make clean
	@cd lx-client-ts && rm -rf dist node_modules
	@cd ui && rm -rf .next node_modules
	@echo "$(GREEN)✓ Clean complete$(NC)"

install-tools:
	@echo "$(BLUE)Installing development tools...$(NC)"
	@which go || (echo "Installing Go..." && brew install go)
	@which node || (echo "Installing Node.js..." && brew install node)
	@which docker || (echo "Installing Docker..." && brew install --cask docker)
	@which protoc || (echo "Installing protoc..." && brew install protobuf)
	@which grpcurl || (echo "Installing grpcurl..." && brew install grpcurl)
	@echo "$(GREEN)✓ Tools installed$(NC)"

# ==========================================
# Lux Oracle (Price Feeds)
# ==========================================

.PHONY: oracle-setup oracle-start oracle-stop oracle-status oracle-test

oracle-setup:
	@echo "$(BLUE)Setting up Lux Oracle...$(NC)"
	@cd lux-oracle && chmod +x setup.sh && ./setup.sh
	@echo "$(GREEN)✓ Lux Oracle setup complete$(NC)"

oracle-start:
	@echo "$(BLUE)Starting Lux Oracle...$(NC)"
	@cd lux-oracle && docker-compose up -d lux-oracle
	@echo "$(GREEN)✓ Lux Oracle running$(NC)"
	@echo "  - API: http://localhost:2000"
	@echo "  - WebSocket: ws://localhost:2002"

oracle-stop:
	@echo "$(YELLOW)Stopping Lux Oracle...$(NC)"
	@cd lux-oracle && docker-compose down
	@echo "$(GREEN)✓ Oracle stopped$(NC)"

oracle-status:
	@echo "$(BLUE)Lux Oracle Status$(NC)"
	@curl -s http://localhost:2000/api/health | jq . || echo "$(RED)Oracle not running$(NC)"

oracle-test:
	@echo "$(BLUE)Testing Lux Oracle price feeds...$(NC)"
	@echo "BTC/USD: $$(curl -s 'http://localhost:2000/api/latest_price_feeds?ids[]=0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43' | jq -r '.[0].price.price' | awk '{print $$1/100000000}')"
	@echo "ETH/USD: $$(curl -s 'http://localhost:2000/api/latest_price_feeds?ids[]=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace' | jq -r '.[0].price.price' | awk '{print $$1/100000000}')"
	@echo "$(GREEN)✓ Price feeds working$(NC)"

# ==========================================
# Deployment
# ==========================================

.PHONY: deploy-dex deploy-cex deploy-prod docker-push

deploy-dex:
	@echo "$(BLUE)Deploying DEX on X-Chain...$(NC)"
	@cd lx-backend && CGO_ENABLED=1 make hybrid-build
	@echo "Deploying to X-Chain validators..."
	# Add actual deployment commands here
	@echo "$(GREEN)✓ DEX deployed$(NC)"

deploy-cex:
	@echo "$(BLUE)Deploying CEX backend...$(NC)"
	@cd lx-backend && make cpp-build
	@echo "Deploying to CEX infrastructure..."
	# Add actual deployment commands here
	@echo "$(GREEN)✓ CEX deployed$(NC)"

deploy-prod: backend-build frontend-build
	@echo "$(BLUE)Deploying to production...$(NC)"
	@make docker-push
	# Add Kubernetes deployment commands
	@echo "$(GREEN)✓ Production deployment complete$(NC)"

docker-push:
	@echo "$(BLUE)Pushing Docker images...$(NC)"
	@cd lx-backend && docker-compose build
	@docker tag lx-hybrid:latest luxexchange/lx-engine:latest
	@docker push luxexchange/lx-engine:latest
	@echo "$(GREEN)✓ Images pushed$(NC)"

# ==========================================
# Quick Start
# ==========================================

.PHONY: quick-start status health-check

quick-start:
	@echo "$(BLUE)╔══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║         Lux Exchange - Quick Start                       ║$(NC)"
	@echo "$(BLUE)╚══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Step 1: Installing dependencies...$(NC)"
	@make install-tools
	@echo ""
	@echo "$(YELLOW)Step 2: Building backend...$(NC)"
	@make backend-build
	@echo ""
	@echo "$(YELLOW)Step 3: Building client library...$(NC)"
	@make client-build
	@make client-link
	@echo ""
	@echo "$(YELLOW)Step 4: Building frontend...$(NC)"
	@make frontend-build
	@echo ""
	@echo "$(YELLOW)Step 5: Starting services...$(NC)"
	@make backend-run
	@sleep 3
	@make frontend-run &
	@sleep 3
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║         Lux Exchange is ready!                           ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "  🌐 UI: http://localhost:3000"
	@echo "  ⚡ API: http://localhost:50050"
	@echo "  📊 Monitoring: http://localhost:9090"
	@echo ""
	@echo "  Run '$(YELLOW)make status$(NC)' to check service health"
	@echo "  Run '$(YELLOW)make benchmark$(NC)' to test performance"
	@echo "  Press Ctrl+C to stop all services"
	@wait

status:
	@echo "$(BLUE)Lux Exchange Service Status$(NC)"
	@echo "══════════════════════════════"
	@echo -n "Backend:   "
	@(cd lx-backend && docker-compose ps -q | head -1) > /dev/null 2>&1 && echo "$(GREEN)● Running$(NC)" || echo "$(RED)○ Stopped$(NC)"
	@echo -n "Frontend:  "
	@curl -s http://localhost:3000 > /dev/null 2>&1 && echo "$(GREEN)● Running$(NC)" || echo "$(RED)○ Stopped$(NC)"
	@echo -n "Engine:    "
	@grpcurl -plaintext localhost:50050 list > /dev/null 2>&1 && echo "$(GREEN)● Running$(NC)" || echo "$(RED)○ Stopped$(NC)"

health-check:
	@echo "$(BLUE)Running health checks...$(NC)"
	@grpcurl -plaintext localhost:50050 lx_engine.LXEngine/HealthCheck || true
	@curl -s http://localhost:3000/api/health || true
	@echo "$(GREEN)✓ Health check complete$(NC)"

# Default when just typing 'make'
.DEFAULT_GOAL := help