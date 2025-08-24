.PHONY: all build test clean install run docker help

# Variables
BINARY_NAME=adx
DOCKER_IMAGE=luxfi/adx
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME=$(shell date -u '+%Y-%m-%d_%H:%M:%S')
LDFLAGS=-ldflags "-X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME}"
GOFLAGS=-v
COVERAGE_FILE=coverage.out

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
NC=\033[0m # No Color

# Default target
all: clean test build

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  ${GREEN}%-15s${NC} %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Build targets
build: ## Build the ADX binary
	@echo "${GREEN}Building ADX...${NC}"
	go build ${GOFLAGS} ${LDFLAGS} -o bin/${BINARY_NAME} ./cmd/adx

build-all: ## Build all binaries
	@echo "${GREEN}Building all binaries...${NC}"
	go build ${GOFLAGS} ${LDFLAGS} -o bin/adx ./cmd/adx
	go build ${GOFLAGS} ${LDFLAGS} -o bin/adx-miner ./cmd/miner
	go build ${GOFLAGS} ${LDFLAGS} -o bin/adx-metrics ./cmd/metrics

build-linux: ## Build for Linux
	@echo "${GREEN}Building for Linux...${NC}"
	GOOS=linux GOARCH=amd64 go build ${GOFLAGS} ${LDFLAGS} -o bin/${BINARY_NAME}-linux ./cmd/adx

build-mac: ## Build for macOS
	@echo "${GREEN}Building for macOS...${NC}"
	GOOS=darwin GOARCH=amd64 go build ${GOFLAGS} ${LDFLAGS} -o bin/${BINARY_NAME}-darwin-amd64 ./cmd/adx
	GOOS=darwin GOARCH=arm64 go build ${GOFLAGS} ${LDFLAGS} -o bin/${BINARY_NAME}-darwin-arm64 ./cmd/adx

build-windows: ## Build for Windows
	@echo "${GREEN}Building for Windows...${NC}"
	GOOS=windows GOARCH=amd64 go build ${GOFLAGS} ${LDFLAGS} -o bin/${BINARY_NAME}.exe ./cmd/adx

# Test targets
test: ## Run all tests
	@echo "${GREEN}Running tests...${NC}"
	go test ./pkg/... ./cmd/... -v -cover

test-coverage: ## Run tests with coverage report
	@echo "${GREEN}Running tests with coverage...${NC}"
	go test ./pkg/... -v -coverprofile=${COVERAGE_FILE}
	go tool cover -func=${COVERAGE_FILE}
	@echo "${YELLOW}Total Coverage:${NC}"
	@go tool cover -func=${COVERAGE_FILE} | grep total | awk '{print $$3}'

test-coverage-html: test-coverage ## Generate HTML coverage report
	@echo "${GREEN}Generating HTML coverage report...${NC}"
	go tool cover -html=${COVERAGE_FILE} -o coverage.html
	@echo "${GREEN}Coverage report generated: coverage.html${NC}"

test-race: ## Run tests with race detector
	@echo "${GREEN}Running tests with race detector...${NC}"
	go test ./pkg/... -race

test-short: ## Run short tests
	@echo "${GREEN}Running short tests...${NC}"
	go test ./pkg/... -short

test-bench: ## Run benchmarks
	@echo "${GREEN}Running benchmarks...${NC}"
	go test ./pkg/... -bench=. -benchmem

test-pkg: ## Test specific package (use PKG=package_name)
	@echo "${GREEN}Testing package ${PKG}...${NC}"
	go test ./pkg/${PKG} -v -cover

# Lint and format
lint: ## Run linter
	@echo "${GREEN}Running linter...${NC}"
	@which golangci-lint > /dev/null || (echo "${RED}golangci-lint not installed${NC}" && exit 1)
	golangci-lint run ./...

fmt: ## Format code
	@echo "${GREEN}Formatting code...${NC}"
	go fmt ./...
	gofmt -s -w .

vet: ## Run go vet
	@echo "${GREEN}Running go vet...${NC}"
	go vet ./...

tidy: ## Run go mod tidy
	@echo "${GREEN}Tidying modules...${NC}"
	go mod tidy

# Docker targets
docker-build: ## Build Docker image
	@echo "${GREEN}Building Docker image...${NC}"
	docker build -t ${DOCKER_IMAGE}:${VERSION} -t ${DOCKER_IMAGE}:latest .

docker-push: ## Push Docker image to registry
	@echo "${GREEN}Pushing Docker image...${NC}"
	docker push ${DOCKER_IMAGE}:${VERSION}
	docker push ${DOCKER_IMAGE}:latest

docker-run: ## Run Docker container
	@echo "${GREEN}Running Docker container...${NC}"
	docker run -p 8080:8080 -p 8081:8081 ${DOCKER_IMAGE}:latest

# Docker Compose targets
up: ## Start all services with Docker Compose
	@echo "${GREEN}Starting services...${NC}"
	docker-compose -f docker/compose.yml up -d

down: ## Stop all services
	@echo "${GREEN}Stopping services...${NC}"
	docker-compose -f docker/compose.yml down

restart: down up ## Restart all services

logs: ## Follow logs
	docker-compose -f docker/compose.yml logs -f

status: ## Show service status
	docker-compose -f docker/compose.yml ps

# Kubernetes targets
k8s-deploy: ## Deploy to Kubernetes
	@echo "${GREEN}Deploying to Kubernetes...${NC}"
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/deployment.yaml

k8s-delete: ## Delete from Kubernetes
	@echo "${YELLOW}Deleting from Kubernetes...${NC}"
	kubectl delete -f k8s/deployment.yaml
	kubectl delete -f k8s/namespace.yaml

k8s-status: ## Show Kubernetes status
	kubectl get all -n adx

# SDK targets
sdk-go: ## Build Go SDK
	@echo "${GREEN}Building Go SDK...${NC}"
	cd sdk/go && go build ./...

sdk-typescript: ## Build TypeScript SDK
	@echo "${GREEN}Building TypeScript SDK...${NC}"
	cd sdk/typescript && npm install && npm run build

sdk-python: ## Build Python SDK
	@echo "${GREEN}Building Python SDK...${NC}"
	cd sdk/python && pip install -e .

sdk-all: sdk-go sdk-typescript sdk-python ## Build all SDKs

# Development targets
run: build ## Run the application
	@echo "${GREEN}Running ADX...${NC}"
	./bin/${BINARY_NAME}

run-miner: ## Run miner
	@echo "${GREEN}Running miner...${NC}"
	go run ./cmd/miner

run-metrics: ## Run metrics server
	@echo "${GREEN}Running metrics server...${NC}"
	go run ./cmd/metrics

dev: ## Run in development mode with hot reload
	@echo "${GREEN}Running in dev mode...${NC}"
	@which air > /dev/null || (echo "${RED}air not installed. Run: go install github.com/cosmtrek/air@latest${NC}" && exit 1)
	air

# Installation
install: build ## Install binary to GOPATH/bin
	@echo "${GREEN}Installing ${BINARY_NAME}...${NC}"
	go install ${LDFLAGS} ./cmd/adx

install-deps: ## Install dependencies
	@echo "${GREEN}Installing dependencies...${NC}"
	go mod download
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/cosmtrek/air@latest

# Database targets
db-setup: ## Setup FoundationDB (requires fdbcli)
	@echo "${GREEN}Setting up FoundationDB...${NC}"
	@which fdbcli > /dev/null || (echo "${RED}fdbcli not installed${NC}" && exit 1)
	fdbcli --exec "configure new single ssd"

# Monitoring
metrics: ## Show metrics
	@echo "${GREEN}Opening metrics dashboard...${NC}"
	open http://localhost:9090/metrics

grafana: ## Open Grafana dashboard
	@echo "${GREEN}Opening Grafana...${NC}"
	open http://localhost:3000

prometheus: ## Open Prometheus
	@echo "${GREEN}Opening Prometheus...${NC}"
	open http://localhost:9090

# Cleanup
clean: ## Clean build artifacts
	@echo "${YELLOW}Cleaning...${NC}"
	rm -rf bin/
	rm -f ${COVERAGE_FILE}
	rm -f coverage.html
	go clean -cache

clean-docker: ## Clean Docker artifacts
	@echo "${YELLOW}Cleaning Docker...${NC}"
	docker-compose -f docker/compose.yml down -v
	docker system prune -f

clean-all: clean clean-docker ## Clean everything
	@echo "${YELLOW}Cleaning everything...${NC}"
	rm -rf vendor/
	go clean -modcache

# Release targets
release: test build-all ## Create release
	@echo "${GREEN}Creating release ${VERSION}...${NC}"
	mkdir -p releases/${VERSION}
	cp bin/* releases/${VERSION}/
	tar -czf releases/adx-${VERSION}.tar.gz -C releases/${VERSION} .
	@echo "${GREEN}Release created: releases/adx-${VERSION}.tar.gz${NC}"

# Check targets
check: fmt vet lint test ## Run all checks
	@echo "${GREEN}All checks passed!${NC}"

check-quick: fmt vet test-short ## Run quick checks
	@echo "${GREEN}Quick checks passed!${NC}"

# Info targets
version: ## Show version
	@echo "${VERSION}"

info: ## Show build info
	@echo "Binary: ${BINARY_NAME}"
	@echo "Version: ${VERSION}"
	@echo "Docker Image: ${DOCKER_IMAGE}"
	@echo "Build Time: ${BUILD_TIME}"

.DEFAULT_GOAL := help