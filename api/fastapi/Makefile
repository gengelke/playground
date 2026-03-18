SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/../..)
API_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
PYTHON ?= python3
API_PORT ?= 8000
API_URL ?= http://127.0.0.1:$(API_PORT)
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml

VENV_DIR ?= $(MAKEFILE_DIR).venv
VENV_PIP := $(VENV_DIR)/bin/pip
UVICORN := $(VENV_DIR)/bin/uvicorn
DEPS_STAMP := $(VENV_DIR)/.deps-installed
UVICORN_MATCH := $(UVICORN) main:app --host 127.0.0.1 --port $(API_PORT)

BARE_STATE_DIR ?= $(MAKEFILE_DIR)runtime/bare
RUNTIME_DIR ?= $(MAKEFILE_DIR)runtime
PID_FILE ?= $(BARE_STATE_DIR)/fastapi.pid
LOG_FILE ?= $(BARE_STATE_DIR)/fastapi.log
DOCKER_DATA_DIR ?= $(MAKEFILE_DIR)data
DOCKER_LOG_FILE ?= $(DOCKER_DATA_DIR)/fastapi.log
DATABASE_PATH ?= $(MAKEFILE_DIR)company.sqlite
LEGACY_DATABASE_PATH ?= $(API_DIR)/company.sqlite

.PHONY: help build up down restart logs status run clean distclean \
	check-mode venv deps \
	docker-build docker-up docker-down docker-logs docker-status \
	bare-build bare-up bare-down bare-logs bare-status

venv:
	@if [[ ! -x "$(VENV_PIP)" ]]; then \
		rm -rf "$(VENV_DIR)"; \
		"$(PYTHON)" -m venv "$(VENV_DIR)"; \
	fi

$(DEPS_STAMP): requirements.txt | venv
	@"$(VENV_PIP)" install --upgrade pip
	@"$(VENV_PIP)" install -r requirements.txt
	@touch "$(DEPS_STAMP)"

deps: $(DEPS_STAMP)

build: check-mode
	@$(MAKE) $(MODE)-build MODE="$(MODE)"

up: check-mode
	@$(MAKE) $(MODE)-up MODE="$(MODE)"

down: check-mode
	@$(MAKE) $(MODE)-down MODE="$(MODE)"

restart:
	@$(MAKE) down MODE="$(MODE)"
	@$(MAKE) up MODE="$(MODE)"

logs: check-mode
	@$(MAKE) $(MODE)-logs MODE="$(MODE)"

status: check-mode
	@$(MAKE) $(MODE)-status MODE="$(MODE)"

run: deps
	@cd "$(MAKEFILE_DIR)" && DATABASE_PATH="$(DATABASE_PATH)" \
		"$(UVICORN)" main:app --host 127.0.0.1 --port "$(API_PORT)"

docker-build:
	@API_PORT="$(API_PORT)" $(DOCKER_COMPOSE) build fastapi

docker-up:
	@mkdir -p "$(DOCKER_DATA_DIR)"
	@API_PORT="$(API_PORT)" $(DOCKER_COMPOSE) up --build -d fastapi
	@for i in $$(seq 1 30); do \
		if curl -fsS "$(API_URL)/schema.graphql" >/dev/null 2>&1; then \
			echo "FastAPI is ready at $(API_URL)"; \
			echo "Docker log file available on host at $(DOCKER_LOG_FILE)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "FastAPI did not become ready in time."; \
	$(MAKE) docker-down MODE=docker >/dev/null; \
	exit 1

docker-down:
	@API_PORT="$(API_PORT)" $(DOCKER_COMPOSE) down

docker-logs:
	@API_PORT="$(API_PORT)" $(DOCKER_COMPOSE) logs -f --tail=100 fastapi

docker-status:
	@API_PORT="$(API_PORT)" $(DOCKER_COMPOSE) ps fastapi

bare-build: deps

bare-up: bare-build
	@mkdir -p "$(BARE_STATE_DIR)"
	@if [[ -f "$(PID_FILE)" ]]; then \
		pid="$$(cat "$(PID_FILE)" 2>/dev/null || true)"; \
		if [[ -n "$$pid" ]] && kill -0 "$$pid" 2>/dev/null; then \
			echo "FastAPI is already running (PID $$pid)"; \
			exit 0; \
		fi; \
		rm -f "$(PID_FILE)"; \
	fi
	@if pids="$$(pgrep -f '$(UVICORN_MATCH)' || true)"; [[ -n "$$pids" ]]; then \
		echo "FastAPI is already running (PID(s) $$pids)"; \
		exit 0; \
	fi
	@cd "$(MAKEFILE_DIR)" && DATABASE_PATH="$(DATABASE_PATH)" \
		nohup "$(UVICORN)" main:app --host 127.0.0.1 --port "$(API_PORT)" \
		>"$(LOG_FILE)" 2>&1 & echo $$! >"$(PID_FILE)"
	@for i in $$(seq 1 30); do \
		if curl -fsS "$(API_URL)/docs" >/dev/null 2>&1; then \
			echo "FastAPI is ready at $(API_URL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "FastAPI did not become ready in time."; \
	$(MAKE) bare-down MODE=bare >/dev/null; \
	exit 1

bare-down:
	@pid="$$(cat "$(PID_FILE)" 2>/dev/null || true)"; \
	if [[ -n "$$pid" ]] && ! kill -0 "$$pid" 2>/dev/null; then \
		rm -f "$(PID_FILE)"; \
		pid=""; \
	fi; \
	if [[ -z "$$pid" ]]; then \
		pid="$$(pgrep -f '$(UVICORN_MATCH)' | head -n1 || true)"; \
	fi; \
	if [[ -z "$$pid" ]]; then \
		rm -f "$(PID_FILE)"; \
		echo "FastAPI is not running."; \
		exit 0; \
	fi; \
	kill "$$pid" 2>/dev/null || true; \
	for _ in $$(seq 1 20); do \
		if ! kill -0 "$$pid" 2>/dev/null; then \
			rm -f "$(PID_FILE)"; \
			echo "Stopped FastAPI (PID $$pid)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	kill -9 "$$pid" 2>/dev/null || true; \
	rm -f "$(PID_FILE)"; \
	echo "Force-stopped FastAPI (PID $$pid)"

bare-logs:
	@mkdir -p "$(BARE_STATE_DIR)"
	@touch "$(LOG_FILE)"
	@tail -f "$(LOG_FILE)"

bare-status:
	@if [[ ! -f "$(PID_FILE)" ]]; then \
		echo "FastAPI (bare mode): not running."; \
		exit 0; \
	fi; \
	pid="$$(cat "$(PID_FILE)" 2>/dev/null || true)"; \
	if [[ -n "$$pid" ]] && kill -0 "$$pid" 2>/dev/null; then \
		echo "FastAPI (bare mode): running (PID $$pid) on $(API_URL)."; \
	else \
		echo "FastAPI (bare mode): stale PID file."; \
	fi

clean:
	@$(MAKE) down MODE=docker >/dev/null 2>&1 || true
	@$(MAKE) down MODE=bare >/dev/null 2>&1 || true
	@find "$(MAKEFILE_DIR)" -type d -name "__pycache__" -prune -exec rm -rf {} +
	@find "$(MAKEFILE_DIR)" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
	@rm -rf "$(RUNTIME_DIR)"

distclean: clean
	@rm -rf "$(VENV_DIR)" "$(DOCKER_DATA_DIR)" "$(DATABASE_PATH)" "$(LEGACY_DATABASE_PATH)"

help:
	@printf "%s\n" \
		"Usage:" \
		"  make build MODE=docker|bare" \
		"  make up MODE=docker|bare" \
		"  make down MODE=docker|bare" \
		"  make logs MODE=docker|bare" \
		"  make status MODE=docker|bare" \
		"  make run MODE=bare" \
		"" \
		"Key variables:" \
		"  MODE=$(MODE)" \
		"  API_PORT=$(API_PORT)" \
		"  API_URL=$(API_URL)" \
		"  DOCKER_LOG_FILE=$(DOCKER_LOG_FILE)" \
		"  LOG_FILE=$(LOG_FILE)" \
		"  DATABASE_PATH=$(DATABASE_PATH)" \
		"  LEGACY_DATABASE_PATH=$(LEGACY_DATABASE_PATH)"
