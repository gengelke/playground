# ==========================================
# Configuration
# ==========================================

VENV := .venv
PIP := $(VENV)/bin/pip
PYTHON := $(VENV)/bin/python3
EMPLOYEECLI := $(VENV)/bin/employee-cli

all: build install test example #cli-list

# ==========================================
# Setup
# ==========================================

.PHONY: venv
venv:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install pydantic httpx fastapi uvicorn
	$(PIP) install pytest pytest-asyncio

# ==========================================
# Install project
# ==========================================

.PHONY: install
install: venv
	$(PIP) install -e .

# ==========================================
# Run FastAPI
# ==========================================

.PHONY: build
build:
	UID=$$(id -u) GID=$$(id -g) docker compose up --build -d

# ==========================================
# Run pytest
# ==========================================

.PHONY: test
test: venv
	.venv/bin/pytest -v

# ==========================================
# Run CLI
# ==========================================

.PHONY: cli-list
cli-list: venv
	$(EMPLOYEECLI) list

# ==========================================
# Run example
# ==========================================

.PHONY: example
example: venv
	$(PYTHON) example_client.py

# ==========================================
# Clean build artifacts
# ==========================================

.PHONY: clean
clean:
	docker compose down
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.un~" -delete
	rm -rf generated_client
	rm -rf dist
	rm -rf *.egg-info
	rm -rf .pytest_cache
	rm -rf .mypy_cache
	rm -rf htmlcov
	rm -rf .coverage
	rm -f schema.graphql schema.json


# ==========================================
# Full reset (includes DB + venv)
# ==========================================

.PHONY: clean-all
clean-all: clean
	rm -rf $(VENV)
	rm -f *.sqlite
	rm -f *.db
	docker rmi api-codegen:latest api-fastapi:latest

# ==========================================
# Regenerate client (optional placeholder)
# ==========================================

.PHONY: codegen
codegen:
	UID=$$(id -u) GID=$$(id -g) docker compose run codegen

# ==========================================
# Show help
# ==========================================

.PHONY: help
help:
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "make venv        - create virtual environment"
	@echo "make install     - install project (editable)"
	@echo "make run         - start FastAPI server"
	@echo "make cli-list    - run CLI to list employees"
	@echo "make clean       - remove build artifacts"
	@echo "make clean-all   - remove artifacts + venv + sqlite db"
	@echo "make codegen     - regenerate GraphQL client"
	@echo ""
