SHELL := /bin/bash

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)

MODE ?= docker
VAULT_ADDR ?= http://127.0.0.1:8200
VAULT_PORT ?= 8200

DOCKER_COMPOSE ?= docker compose
DOCKER_PROJECT ?= vault-local

BARE_CONFIG ?= ./config/vault-bare.hcl
BARE_PID_FILE ?= ./.vault/vault.pid
BARE_LOG_FILE ?= ./.vault/logs/vault.log
CREDS_FILE ?= ./.vault/credentials.env
BOOTSTRAP_SCRIPT ?= ./scripts/bootstrap-vault.sh

export VAULT_PORT

.PHONY: help up down restart logs status clean creds bare-up bare-down docker-up docker-down

help:
	@echo "Vault OSS local setup"
	@echo ""
	@echo "Usage:"
	@echo "  make up MODE=docker"
	@echo "  make up MODE=bare"
	@echo "  make down MODE=docker"
	@echo "  make down MODE=bare"
	@echo ""
	@echo "Optional:"
	@echo "  make logs MODE=docker|bare"
	@echo "  make status MODE=docker|bare"
	@echo "  make restart MODE=docker|bare"
	@echo "  make creds"
	@echo "  make clean"
	@echo ""
	@echo "Environment:"
	@echo "  VAULT_ADDR=$(VAULT_ADDR)"

up:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) docker-up; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		$(MAKE) bare-up; \
	else \
		echo "Unsupported MODE='$(MODE)'. Use MODE=docker or MODE=bare."; \
		exit 1; \
	fi

down:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) docker-down; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		$(MAKE) bare-down; \
	else \
		echo "Unsupported MODE='$(MODE)'. Use MODE=docker or MODE=bare."; \
		exit 1; \
	fi

restart: down up

logs:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(DOCKER_COMPOSE) --project-name "$(DOCKER_PROJECT)" logs -f vault; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		if [[ -f "$(BARE_LOG_FILE)" ]]; then tail -n 100 -f "$(BARE_LOG_FILE)"; else echo "No bare log file found at $(BARE_LOG_FILE)"; fi; \
	else \
		echo "Unsupported MODE='$(MODE)'. Use MODE=docker or MODE=bare."; \
		exit 1; \
	fi

status:
	@echo "VAULT_ADDR=$(VAULT_ADDR)"
	@http_code="$$(curl -s -o /dev/null -w "%{http_code}" "$(VAULT_ADDR)/v1/sys/health" 2>/dev/null || true)"; \
	if [[ -n "$$http_code" && "$$http_code" != "000" ]]; then \
		echo "Vault API reachable at $(VAULT_ADDR)"; \
		echo "Health endpoint HTTP status: $$http_code"; \
	else \
		echo "Vault API not reachable at $(VAULT_ADDR)"; \
	fi
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(DOCKER_COMPOSE) --project-name "$(DOCKER_PROJECT)" ps; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		if [[ -f "$(BARE_PID_FILE)" ]] && kill -0 "$$(cat "$(BARE_PID_FILE)")" 2>/dev/null; then \
			echo "Bare Vault running with PID $$(cat "$(BARE_PID_FILE)")"; \
		else \
			echo "Bare Vault not running"; \
		fi; \
	else \
		echo "Unsupported MODE='$(MODE)'. Use MODE=docker or MODE=bare."; \
		exit 1; \
	fi

docker-up:
	@command -v docker >/dev/null 2>&1 || { echo "docker is required for MODE=docker"; exit 1; }
	@mkdir -p ./.vault/data
	@$(DOCKER_COMPOSE) --project-name "$(DOCKER_PROJECT)" up -d --force-recreate
	@VAULT_ADDR="$(VAULT_ADDR)" CREDS_FILE="$(CREDS_FILE)" bash "$(BOOTSTRAP_SCRIPT)"
	@echo "Vault (docker mode) started on $(VAULT_ADDR)"
	@echo "Run: export VAULT_ADDR=$(VAULT_ADDR)"

docker-down:
	@command -v docker >/dev/null 2>&1 || { echo "docker is required for MODE=docker"; exit 1; }
	@$(DOCKER_COMPOSE) --project-name "$(DOCKER_PROJECT)" down
	@echo "Vault (docker mode) stopped"

bare-up:
	@command -v vault >/dev/null 2>&1 || { echo "vault CLI/server binary is required for MODE=bare"; exit 1; }
	@mkdir -p ./.vault/data ./.vault/logs
	@if [[ -f "$(BARE_PID_FILE)" ]] && kill -0 "$$(cat "$(BARE_PID_FILE)")" 2>/dev/null; then \
		echo "Vault already running in bare mode with PID $$(cat "$(BARE_PID_FILE)")"; \
		exit 0; \
	fi
	@nohup vault server -config="$(BARE_CONFIG)" >"$(BARE_LOG_FILE)" 2>&1 & echo $$! >"$(BARE_PID_FILE)"
	@sleep 1
	@if kill -0 "$$(cat "$(BARE_PID_FILE)")" 2>/dev/null; then \
		VAULT_ADDR="$(VAULT_ADDR)" CREDS_FILE="$(CREDS_FILE)" bash "$(BOOTSTRAP_SCRIPT)"; \
		echo "Vault (bare mode) started with PID $$(cat "$(BARE_PID_FILE)") on $(VAULT_ADDR)"; \
		echo "Log: $(BARE_LOG_FILE)"; \
		echo "Run: export VAULT_ADDR=$(VAULT_ADDR)"; \
	else \
		echo "Failed to start Vault in bare mode. Check $(BARE_LOG_FILE)"; \
		exit 1; \
	fi

bare-down:
	@if [[ -f "$(BARE_PID_FILE)" ]]; then \
		pid="$$(cat "$(BARE_PID_FILE)")"; \
		if kill -0 "$$pid" 2>/dev/null; then \
			kill "$$pid"; \
			for _ in 1 2 3 4 5; do \
				if ! kill -0 "$$pid" 2>/dev/null; then break; fi; \
				sleep 1; \
			done; \
			if kill -0 "$$pid" 2>/dev/null; then \
				echo "PID $$pid did not exit in time; forcing stop"; \
				kill -9 "$$pid"; \
			fi; \
			echo "Vault (bare mode) stopped"; \
		else \
			echo "No running process found for PID $$pid"; \
		fi; \
		rm -f "$(BARE_PID_FILE)"; \
	else \
		echo "No bare Vault PID file found"; \
	fi

creds:
	@if [[ -f "$(CREDS_FILE)" ]]; then \
		set -a; source "$(CREDS_FILE)"; set +a; \
		echo "Credentials file: $(CREDS_FILE)"; \
		echo "VAULT_ADDR=$${VAULT_ADDR:-$(VAULT_ADDR)}"; \
		echo "Root Token: $${VAULT_ROOT_TOKEN:-<missing>}"; \
		echo "Unseal Key: $${VAULT_UNSEAL_KEY:-<missing>}"; \
		echo "Login: vault login $${VAULT_ROOT_TOKEN:-<missing>}"; \
	else \
		echo "No credentials file found at $(CREDS_FILE)"; \
		exit 1; \
	fi

clean:
	@$(MAKE) docker-down >/dev/null 2>&1 || true
	@$(MAKE) bare-down >/dev/null 2>&1 || true
	@rm -rf ./.vault
	@echo "Removed local Vault state at ./.vault"
