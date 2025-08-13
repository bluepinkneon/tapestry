# Tapestry Makefile
.PHONY: all build test lint format clean help install

# Default target
all: lint build test

# Help command
help:
	@echo "Available commands:"
	@echo "  make install    - Install dependencies"
	@echo "  make lint       - Run all linters"
	@echo "  make format     - Format code"
	@echo "  make build      - Compile contracts"
	@echo "  make test       - Run tests"
	@echo "  make coverage   - Generate coverage report"
	@echo "  make gas        - Generate gas report"
	@echo "  make security   - Run security analysis"
	@echo "  make clean      - Clean build artifacts"

# Install dependencies
install:
	npm install
	forge install

# Linting
lint: lint-sol lint-format

lint-sol:
	@echo "Running Solhint..."
	npx solhint --config .solhint.json 'src/**/*.sol'

lint-format:
	@echo "Checking Forge formatting..."
	forge fmt --check

# Formatting
format:
	@echo "Formatting contracts..."
	forge fmt

# Building
build:
	@echo "Building contracts..."
	forge build --sizes

# Testing
test:
	@echo "Running tests..."
	forge test -vvv

test-gas:
	@echo "Running tests with gas reporting..."
	forge test --gas-report

# Coverage
coverage:
	@echo "Generating coverage report..."
	forge coverage --report summary
	forge coverage --report lcov

# Gas optimization
gas:
	@echo "Creating gas snapshot..."
	forge snapshot

gas-diff:
	@echo "Comparing gas usage..."
	forge snapshot --diff

# Security
security:
	@echo "Running Slither security analysis..."
	slither src/ --print human-summary || true

# Clean
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf out cache

# Deploy scripts
deploy-local:
	@echo "Deploying to local network..."
	forge script script/Deploy.s.sol --rpc-url localhost --broadcast

deploy-testnet:
	@echo "Deploying to testnet..."
	@read -p "Enter RPC URL: " rpc_url; \
	forge script script/Deploy.s.sol --rpc-url $$rpc_url --broadcast --verify

# Pre-commit
pre-commit: lint-sol lint-format build test
	@echo "All pre-commit checks passed!"

# CI simulation
ci: install lint build test coverage
	@echo "CI checks complete!"