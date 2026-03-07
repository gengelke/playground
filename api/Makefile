# ==========================================
# Configuration
# ==========================================

VENV           := .venv
PIP            := $(VENV)/bin/pip
PYTHON         := $(VENV)/bin/python3
PYTEST         := $(VENV)/bin/pytest
UVICORN        := $(VENV)/bin/uvicorn
EMPLOYEECLI    := $(VENV)/bin/employee-cli
PID_FILE       := .fastapi.pid
API_URL        ?= http://127.0.0.1:8000
DEPS_STAMP     := $(VENV)/.deps-installed
DOCKER_COMPOSE ?= docker compose

.PHONY: all
all: all-local

# ==========================================
# Workflows
# ==========================================

.PHONY: all-local
all-local:
	@set -e; \
	$(MAKE) run-bg; \
	trap '$(MAKE) stop' EXIT; \
	$(MAKE) codegen; \
	$(MAKE) install; \
	PYTHONPATH=. $(PYTEST) -v; \
	$(PYTHON) example_client.py

.PHONY: all-docker
all-docker:
	$(MAKE) run-docker
	$(MAKE) codegen-docker

# ==========================================
# Setup
# ==========================================

.PHONY: venv
venv:
	@if [ ! -x "$(PIP)" ] || ! "$(PIP)" --version >/dev/null 2>&1; then rm -rf "$(VENV)"; python3 -m venv "$(VENV)"; fi

$(DEPS_STAMP): | venv
	$(PIP) install --upgrade pip
	$(PIP) install "setuptools>=61" wheel
	$(PIP) install pydantic httpx fastapi uvicorn strawberry-graphql
	$(PIP) install pytest pytest-asyncio ariadne-codegen
	touch $(DEPS_STAMP)

.PHONY: deps
deps: $(DEPS_STAMP)

.PHONY: install
install: deps
	$(PIP) install -e . --no-build-isolation

# ==========================================
# Run FastAPI (local)
# ==========================================

.PHONY: run
run: deps
	$(UVICORN) --app-dir fastapi main:app --host 127.0.0.1 --port 8000

.PHONY: run-bg
run-bg: deps stop
	$(UVICORN) --app-dir fastapi main:app --host 127.0.0.1 --port 8000 > .fastapi.log 2>&1 & echo $$! > $(PID_FILE)
	@echo "FastAPI started with PID $$(cat $(PID_FILE))"
	@for i in $$(seq 1 30); do \
		if curl -fsS $(API_URL)/docs >/dev/null 2>&1; then \
			echo "FastAPI is ready at $(API_URL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "FastAPI did not become ready in time."; \
	$(MAKE) stop; \
	exit 1

.PHONY: stop
stop:
	@if [ -f "$(PID_FILE)" ]; then \
		PID=$$(cat $(PID_FILE)); \
		if kill -0 $$PID >/dev/null 2>&1; then \
			kill $$PID; \
			echo "Stopped FastAPI (PID $$PID)"; \
		fi; \
		rm -f $(PID_FILE); \
	fi

# ==========================================
# Docker
# ==========================================

.PHONY: run-docker
run-docker:
	$(DOCKER_COMPOSE) up --build -d fastapi

.PHONY: codegen-docker
codegen-docker:
	$(DOCKER_COMPOSE) run --rm codegen

.PHONY: stop-docker
stop-docker:
	$(DOCKER_COMPOSE) down

.PHONY: clean-docker
clean-docker:
	$(DOCKER_COMPOSE) down --rmi local --volumes --remove-orphans

# ==========================================
# Codegen, test, example, CLI
# ==========================================

.PHONY: codegen
codegen: deps
	bash library-builder/generate-client.sh

.PHONY: test
test: deps
	@set -e; \
	$(MAKE) run-bg; \
	trap '$(MAKE) stop' EXIT; \
	$(MAKE) codegen; \
	$(MAKE) install; \
	PYTHONPATH=. $(PYTEST) -v

.PHONY: example
example: deps
	$(PYTHON) example_client.py

.PHONY: cli-list
cli-list: deps
	$(EMPLOYEECLI) list

# ==========================================
# Clean
# ==========================================

.PHONY: clean
clean: stop
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f \( -name "*.pyc" -o -name "*.pyo" -o -name "*.un~" \) -delete
	rm -rf generated_client dist *.egg-info .pytest_cache .mypy_cache htmlcov
	rm -f .fastapi.log .coverage $(DEPS_STAMP) schema.graphql schema.json

.PHONY: distclean
distclean: clean
	rm -rf $(VENV)
	rm -f *.sqlite *.db

# ==========================================
# Help
# ==========================================

.PHONY: help
help:
	@echo ""
	@echo "Local:"
	@echo "  make all-local      full workflow: server, codegen, test, example"
	@echo "  make run            start FastAPI in foreground"
	@echo "  make run-bg         start FastAPI in background"
	@echo "  make stop           stop background FastAPI"
	@echo "  make codegen        regenerate GraphQL client"
	@echo "  make test           run pytest (manages server automatically)"
	@echo "  make example        run example client"
	@echo "  make cli-list       list employees via CLI"
	@echo ""
	@echo "Docker:"
	@echo "  make all-docker     start Docker API + run codegen"
	@echo "  make run-docker     start FastAPI with Docker"
	@echo "  make codegen-docker regenerate GraphQL client in Docker"
	@echo "  make stop-docker    stop Docker services"
	@echo "  make clean-docker   remove containers/images/volumes"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean          remove build artifacts"
	@echo "  make distclean      remove artifacts + venv + sqlite db"
	@echo ""
