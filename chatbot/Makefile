SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
PYTHON ?= python3.12
CHATBOT_HOST ?= 0.0.0.0
CHATBOT_PORT ?= 8088
CHATBOT_URL ?= http://127.0.0.1:$(CHATBOT_PORT)
CHATBOT_CONFIG ?= $(MAKEFILE_DIR)config/config.yml
LOCAL_LLM_URL ?= http://localhost:11434/api/chat
OLLAMA_DIR ?= $(ROOT_DIR)/ollama
OLLAMA_MODE ?= docker
OLLAMA_MODEL ?= llama3.1
OLLAMA_EMBED_MODEL ?= nomic-embed-text
CHATBOT_START_OLLAMA ?= true
CHATBOT_STOP_OLLAMA ?= true
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml

VENV_DIR ?= $(MAKEFILE_DIR).venv
VENV_PIP := $(VENV_DIR)/bin/pip
VENV_PYTHON := $(VENV_DIR)/bin/python
UVICORN := $(VENV_DIR)/bin/uvicorn
PYTEST := $(VENV_DIR)/bin/pytest
DEPS_STAMP := $(VENV_DIR)/.deps-installed
UVICORN_MATCH := $(UVICORN) app.main:app --host $(CHATBOT_HOST) --port $(CHATBOT_PORT)

RUNTIME_DIR ?= $(MAKEFILE_DIR)runtime
BARE_STATE_DIR ?= $(RUNTIME_DIR)/bare
PID_FILE ?= $(BARE_STATE_DIR)/chatbot.pid
LOG_FILE ?= $(BARE_STATE_DIR)/chatbot.log

.PHONY: help build up down restart logs status run test ingest clean distclean \
	check-mode venv deps ensure-ollama stop-ollama \
	docker-build docker-up docker-run docker-down docker-logs docker-status \
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

ensure-ollama:
ifeq ($(CHATBOT_START_OLLAMA),true)
	@$(MAKE) -C "$(OLLAMA_DIR)" up MODE="$(OLLAMA_MODE)" OLLAMA_MODEL="$(OLLAMA_MODEL)"
	@$(MAKE) -C "$(OLLAMA_DIR)" pull-model MODE="$(OLLAMA_MODE)" OLLAMA_MODEL="$(OLLAMA_EMBED_MODEL)"
endif

stop-ollama:
ifeq ($(CHATBOT_STOP_OLLAMA),true)
	@$(MAKE) -C "$(OLLAMA_DIR)" down MODE="$(OLLAMA_MODE)"
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

run: deps ensure-ollama
	@cd "$(MAKEFILE_DIR)" && CHATBOT_CONFIG="$(CHATBOT_CONFIG)" LOCAL_LLM_URL="$(LOCAL_LLM_URL)" \
		"$(UVICORN)" app.main:app --host "$(CHATBOT_HOST)" --port "$(CHATBOT_PORT)"

test: deps
	@cd "$(MAKEFILE_DIR)" && "$(PYTEST)"

ingest: deps
	@if [[ -z "$(PATHS)" ]]; then \
		echo "Usage: make ingest PATHS='sample_docs [more paths]' [PROFILES='sqlite,qdrant_local_hash']"; \
		exit 1; \
	fi
	@cd "$(MAKEFILE_DIR)" && CHATBOT_CONFIG="$(CHATBOT_CONFIG)" \
		"$(VENV_PYTHON)" -m app.cli ingest $(PATHS) $(if $(PROFILES),--profiles "$(PROFILES)",)

docker-build:
	@CHATBOT_PORT="$(CHATBOT_PORT)" $(DOCKER_COMPOSE) build

docker-up:
	@$(MAKE) ensure-ollama
	@CHATBOT_PORT="$(CHATBOT_PORT)" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" $(DOCKER_COMPOSE) up --build -d
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
	@CHATBOT_PORT="$(CHATBOT_PORT)" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" $(DOCKER_COMPOSE) up --build

docker-down:
	@CHATBOT_PORT="$(CHATBOT_PORT)" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" $(DOCKER_COMPOSE) down
	@$(MAKE) stop-ollama

docker-logs:
	@CHATBOT_PORT="$(CHATBOT_PORT)" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" $(DOCKER_COMPOSE) logs -f --tail=100 chatbot qdrant

docker-status:
	@CHATBOT_PORT="$(CHATBOT_PORT)" LOCAL_LLM_URL="http://playground-ollama:11434/api/chat" $(DOCKER_COMPOSE) ps

bare-build: deps

bare-up: bare-build
	@$(MAKE) ensure-ollama
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
		"  LOCAL_LLM_URL=$(LOCAL_LLM_URL)" \
		"  CHATBOT_START_OLLAMA=$(CHATBOT_START_OLLAMA)" \
		"  OLLAMA_MODEL=$(OLLAMA_MODEL)" \
		"  OLLAMA_EMBED_MODEL=$(OLLAMA_EMBED_MODEL)" \
		"  LOG_FILE=$(LOG_FILE)"
