SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
PYTHON ?= $(shell for candidate in python3.12 python3.11 python3.10 python3; do \
	if command -v "$$candidate" >/dev/null 2>&1; then \
		echo "$$candidate"; \
		break; \
	fi; \
done)
CHATBOT_HOST ?= 0.0.0.0
CHATBOT_PORT ?= 8088
CHATBOT_URL ?= http://127.0.0.1:$(CHATBOT_PORT)
CHATBOT_CONFIG ?= $(MAKEFILE_DIR)config/config.yml
OLLAMA_PORT ?= 11435
OLLAMA_URL ?= http://127.0.0.1:$(OLLAMA_PORT)
LOCAL_LLM_URL ?= $(OLLAMA_URL)/api/chat
OLLAMA_EMBED_URL ?= $(OLLAMA_URL)/api/embed
OLLAMA_DIR ?= $(ROOT_DIR)/ollama
OLLAMA_MODE ?= docker
OLLAMA_MODEL ?= llama3.1
OLLAMA_EMBED_MODEL ?= nomic-embed-text
QDRANT_PORT ?= 6333
QDRANT_URL ?= http://127.0.0.1:$(QDRANT_PORT)
QDRANT_DIR ?= $(ROOT_DIR)/qdrant
QDRANT_MODE ?= docker
CHATBOT_START_OLLAMA ?= true
CHATBOT_STOP_OLLAMA ?= true
CHATBOT_START_QDRANT ?= true
CHATBOT_STOP_QDRANT ?= true
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml

VENV_DIR ?= $(MAKEFILE_DIR).venv
VENV_PIP := $(VENV_DIR)/bin/pip
VENV_PYTHON := $(VENV_DIR)/bin/python
UVICORN := $(VENV_DIR)/bin/uvicorn
PYTEST := $(VENV_DIR)/bin/pytest
DEPS_STAMP := $(VENV_DIR)/.deps-installed
UVICORN_MATCH := $(UVICORN) app.main:app --host $(CHATBOT_HOST) --port $(CHATBOT_PORT)
SANITIZE_TLS_ENV = \
	for cert_var in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE PIP_CERT; do \
		cert_path="$${!cert_var:-}"; \
		if [[ -n "$$cert_path" && ! -f "$$cert_path" ]]; then \
			echo "Ignoring invalid $$cert_var=$$cert_path" >&2; \
			unset "$$cert_var"; \
		fi; \
	done;

RUNTIME_DIR ?= $(MAKEFILE_DIR)runtime
BARE_STATE_DIR ?= $(RUNTIME_DIR)/bare
PID_FILE ?= $(BARE_STATE_DIR)/chatbot.pid
LOG_FILE ?= $(BARE_STATE_DIR)/chatbot.log

.PHONY: help build up down restart logs status run test ingest clean distclean \
	check-mode venv deps ensure-ollama stop-ollama ensure-qdrant stop-qdrant \
	docker-build docker-up docker-run docker-down docker-logs docker-status \
	bare-build bare-up bare-down bare-logs bare-status

venv:
	@if [[ -z "$(PYTHON)" ]]; then \
		echo "No supported Python interpreter found. Install python3.10+ or run make with PYTHON=/path/to/python3.10+"; \
		exit 1; \
	fi
	@"$(PYTHON)" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else "Python 3.10+ is required")'
	@if [[ ! -x "$(VENV_PIP)" ]]; then \
		rm -rf "$(VENV_DIR)"; \
		"$(PYTHON)" -m venv "$(VENV_DIR)"; \
	fi

$(DEPS_STAMP): requirements.txt | venv
	@$(SANITIZE_TLS_ENV) \
		PIP_DISABLE_PIP_VERSION_CHECK=1 "$(VENV_PYTHON)" -m pip install --upgrade pip
	@$(SANITIZE_TLS_ENV) \
		PIP_DISABLE_PIP_VERSION_CHECK=1 "$(VENV_PYTHON)" -m pip install -r requirements.txt
	@touch "$(DEPS_STAMP)"

deps: $(DEPS_STAMP)

ensure-ollama:
ifeq ($(CHATBOT_START_OLLAMA),true)
	@$(MAKE) -C "$(OLLAMA_DIR)" up MODE="$(OLLAMA_MODE)" OLLAMA_MODEL="$(OLLAMA_MODEL)"
	@$(MAKE) -C "$(OLLAMA_DIR)" pull-model MODE="$(OLLAMA_MODE)" OLLAMA_MODEL="$(OLLAMA_EMBED_MODEL)"
endif

stop-ollama:
ifeq ($(CHATBOT_STOP_OLLAMA),true)
	@$(MAKE) -C "$(OLLAMA_DIR)" down MODE="$(OLLAMA_MODE)"
endif

ensure-qdrant:
ifeq ($(CHATBOT_START_QDRANT),true)
	@$(MAKE) -C "$(QDRANT_DIR)" up MODE="$(QDRANT_MODE)"
endif

stop-qdrant:
ifeq ($(CHATBOT_STOP_QDRANT),true)
	@$(MAKE) -C "$(QDRANT_DIR)" down MODE="$(QDRANT_MODE)"
endif

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

run: deps ensure-ollama ensure-qdrant
	@cd "$(MAKEFILE_DIR)" && CHATBOT_CONFIG="$(CHATBOT_CONFIG)" LOCAL_LLM_URL="$(LOCAL_LLM_URL)" OLLAMA_EMBED_URL="$(OLLAMA_EMBED_URL)" QDRANT_URL="$(QDRANT_URL)" \
		"$(UVICORN)" app.main:app --host "$(CHATBOT_HOST)" --port "$(CHATBOT_PORT)"

test: deps
	@cd "$(MAKEFILE_DIR)" && "$(PYTEST)"

ingest: deps
	@if [[ -z "$(PATHS)" ]]; then \
		echo "Usage: make ingest PATHS='sample_docs [more paths]' [PROFILES='sqlite,qdrant_openai']"; \
		exit 1; \
	fi
	@cd "$(MAKEFILE_DIR)" && CHATBOT_CONFIG="$(CHATBOT_CONFIG)" OLLAMA_EMBED_URL="$(OLLAMA_EMBED_URL)" LOCAL_LLM_URL="$(LOCAL_LLM_URL)" QDRANT_URL="$(QDRANT_URL)" \
		"$(VENV_PYTHON)" -m app.cli ingest $(PATHS) $(if $(PROFILES),--profiles "$(PROFILES)",)

docker-build:
	@CHATBOT_PORT="$(CHATBOT_PORT)" $(DOCKER_COMPOSE) build

docker-up:
	@$(MAKE) ensure-ollama
	@$(MAKE) ensure-qdrant
	@CHATBOT_PORT="$(CHATBOT_PORT)" QDRANT_URL="http://playground-qdrant:6333" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" OLLAMA_EMBED_URL="http://playground-ollama:11434/api/embed" $(DOCKER_COMPOSE) up --build -d
	@for _ in $$(seq 1 30); do \
		if curl -fsS "$(CHATBOT_URL)/health" >/dev/null 2>&1; then \
			echo "Chatbot is ready at $(CHATBOT_URL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "Chatbot did not become ready in time."; \
	$(MAKE) docker-down MODE=docker >/dev/null; \
	exit 1

docker-run:
	@$(MAKE) ensure-ollama
	@$(MAKE) ensure-qdrant
	@CHATBOT_PORT="$(CHATBOT_PORT)" QDRANT_URL="http://playground-qdrant:6333" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" OLLAMA_EMBED_URL="http://playground-ollama:11434/api/embed" $(DOCKER_COMPOSE) up --build

docker-down:
	@CHATBOT_PORT="$(CHATBOT_PORT)" QDRANT_URL="http://playground-qdrant:6333" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" OLLAMA_EMBED_URL="http://playground-ollama:11434/api/embed" $(DOCKER_COMPOSE) down
	@$(MAKE) stop-qdrant
	@$(MAKE) stop-ollama

docker-logs:
	@CHATBOT_PORT="$(CHATBOT_PORT)" QDRANT_URL="http://playground-qdrant:6333" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" OLLAMA_EMBED_URL="http://playground-ollama:11434/api/embed" $(DOCKER_COMPOSE) logs -f --tail=100 chatbot

docker-status:
	@CHATBOT_PORT="$(CHATBOT_PORT)" QDRANT_URL="http://playground-qdrant:6333" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" OLLAMA_EMBED_URL="http://playground-ollama:11434/api/embed" $(DOCKER_COMPOSE) ps

bare-build: deps

bare-up: bare-build
	@$(MAKE) ensure-ollama
	@$(MAKE) ensure-qdrant
	@mkdir -p "$(BARE_STATE_DIR)"
	@if [[ -f "$(PID_FILE)" ]]; then \
		pid="$$(cat "$(PID_FILE)" 2>/dev/null || true)"; \
		if [[ -n "$$pid" ]] && kill -0 "$$pid" 2>/dev/null; then \
			echo "Chatbot is already running (PID $$pid) at $(CHATBOT_URL)"; \
			exit 0; \
		fi; \
		rm -f "$(PID_FILE)"; \
	fi
	@if pids="$$(pgrep -f '$(UVICORN_MATCH)' || true)"; [[ -n "$$pids" ]]; then \
		echo "Chatbot is already running (PID(s) $$pids) at $(CHATBOT_URL)"; \
		exit 0; \
	fi
	@cd "$(MAKEFILE_DIR)" && CHATBOT_CONFIG="$(CHATBOT_CONFIG)" LOCAL_LLM_URL="$(LOCAL_LLM_URL)" \
		OLLAMA_EMBED_URL="$(OLLAMA_EMBED_URL)" \
		QDRANT_URL="$(QDRANT_URL)" \
		nohup "$(UVICORN)" app.main:app --host "$(CHATBOT_HOST)" --port "$(CHATBOT_PORT)" \
		>"$(LOG_FILE)" 2>&1 & echo $$! >"$(PID_FILE)"
	@for _ in $$(seq 1 30); do \
		if curl -fsS "$(CHATBOT_URL)/health" >/dev/null 2>&1; then \
			echo "Chatbot is ready at $(CHATBOT_URL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "Chatbot did not become ready in time."; \
	$(MAKE) bare-down MODE=bare >/dev/null; \
	exit 1

bare-down:
	@$(MAKE) stop-qdrant
	@$(MAKE) stop-ollama
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
		echo "Chatbot is not running."; \
		exit 0; \
	fi; \
	kill "$$pid" 2>/dev/null || true; \
	for _ in $$(seq 1 20); do \
		if ! kill -0 "$$pid" 2>/dev/null; then \
			rm -f "$(PID_FILE)"; \
			echo "Stopped chatbot (PID $$pid)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	kill -9 "$$pid" 2>/dev/null || true; \
	rm -f "$(PID_FILE)"; \
	echo "Force-stopped chatbot (PID $$pid)"

bare-logs:
	@mkdir -p "$(BARE_STATE_DIR)"
	@touch "$(LOG_FILE)"
	@tail -f "$(LOG_FILE)"

bare-status:
	@if [[ ! -f "$(PID_FILE)" ]]; then \
		echo "Chatbot (bare mode): not running."; \
		exit 0; \
	fi; \
	pid="$$(cat "$(PID_FILE)" 2>/dev/null || true)"; \
	if [[ -n "$$pid" ]] && kill -0 "$$pid" 2>/dev/null; then \
		echo "Chatbot (bare mode): running (PID $$pid) at $(CHATBOT_URL)."; \
	else \
		echo "Chatbot (bare mode): stale PID file."; \
	fi

clean:
	@$(MAKE) down MODE=docker >/dev/null 2>&1 || true
	@$(MAKE) down MODE=bare >/dev/null 2>&1 || true
	@find "$(MAKEFILE_DIR)" -type d -name "__pycache__" -prune -exec rm -rf {} +
	@find "$(MAKEFILE_DIR)" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
	@rm -rf "$(RUNTIME_DIR)" "$(MAKEFILE_DIR).pytest_cache"

distclean: clean
	@rm -rf "$(VENV_DIR)" "$(MAKEFILE_DIR)data"

help:
	@printf "%s\n" \
		"Usage:" \
		"  make build MODE=docker|bare" \
		"  make up MODE=docker|bare" \
		"  make down MODE=docker|bare" \
		"  make logs MODE=docker|bare" \
		"  make status MODE=docker|bare" \
		"  make run MODE=bare" \
		"  make docker-run" \
		"  make test" \
		"  make ingest PATHS='sample_docs'" \
		"" \
		"Key variables:" \
		"  MODE=$(MODE)" \
		"  PYTHON=$(PYTHON)" \
		"  CHATBOT_HOST=$(CHATBOT_HOST)" \
		"  CHATBOT_PORT=$(CHATBOT_PORT)" \
		"  CHATBOT_URL=$(CHATBOT_URL)" \
		"  CHATBOT_CONFIG=$(CHATBOT_CONFIG)" \
		"  OLLAMA_URL=$(OLLAMA_URL)" \
		"  LOCAL_LLM_URL=$(LOCAL_LLM_URL)" \
		"  OLLAMA_EMBED_URL=$(OLLAMA_EMBED_URL)" \
		"  QDRANT_URL=$(QDRANT_URL)" \
		"  CHATBOT_START_OLLAMA=$(CHATBOT_START_OLLAMA)" \
		"  CHATBOT_START_QDRANT=$(CHATBOT_START_QDRANT)" \
		"  OLLAMA_MODEL=$(OLLAMA_MODEL)" \
		"  OLLAMA_EMBED_MODEL=$(OLLAMA_EMBED_MODEL)" \
		"  LOG_FILE=$(LOG_FILE)"
