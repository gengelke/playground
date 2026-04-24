SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
VAULT_DIR ?= $(ROOT_DIR)/vault
ENV_FILE ?= .env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
DOCKER_COMPOSE ?= docker compose --env-file $(ENV_FILE) -f docker-compose.yml
VAULT_ADDR ?= http://127.0.0.1:8200
ZAMMAD_PORT ?= 8090
ZAMMAD_URL ?= http://127.0.0.1:$(ZAMMAD_PORT)

export ZAMMAD_PORT ZAMMAD_URL

.PHONY: help up down restart logs status ps clean distclean \
	check-mode ensure-env ensure-vault docker-up docker-down docker-logs docker-status \
	bare-up bare-down bare-logs bare-status

help:
	@printf "%s\n" \
		"Usage:" \
		"  make up MODE=docker        # start Zammad and initialize credentials" \
		"  make down MODE=docker      # stop containers, keep volumes and .env" \
		"  make logs MODE=docker      # tail Zammad logs" \
		"  make status MODE=docker    # show container status" \
		"  make distclean             # remove containers, volumes, and generated .env" \
		"  MODE=bare aliases Docker for this service" \
		"" \
		"Key variables:" \
		"  ENV_FILE=$(ENV_FILE)" \
		"  ZAMMAD_PORT=$(ZAMMAD_PORT)" \
		"  ZAMMAD_URL=$(ZAMMAD_URL)" \
		"  VAULT_ADDR=$(VAULT_ADDR)" \
		"" \
		"Notes:" \
		"  Zammad's official Docker stack expects sufficient memory and Elasticsearch support." \
		"  If Elasticsearch fails to start on Linux, set: sudo sysctl -w vm.max_map_count=262144"

ensure-env:
	@if [[ ! -f "$(ENV_FILE)" ]]; then \
		echo "No $(ENV_FILE) found. Copying .env.example -> $(ENV_FILE)"; \
		cp .env.example "$(ENV_FILE)"; \
	fi

ensure-vault: check-mode
	@VAULT_ADDR="$(VAULT_ADDR)" VAULT_DIR="$(VAULT_DIR)" MODE="$(MODE)" \
		bash "$(ROOT_DIR)/scripts/lib/vault-check.sh"

up: check-mode ensure-env
	@$(MAKE) $(MODE)-up MODE="$(MODE)" ENV_FILE="$(ENV_FILE)"

down: check-mode ensure-env
	@$(MAKE) $(MODE)-down MODE="$(MODE)" ENV_FILE="$(ENV_FILE)"

restart:
	@$(MAKE) down MODE="$(MODE)" ENV_FILE="$(ENV_FILE)"
	@$(MAKE) up MODE="$(MODE)" ENV_FILE="$(ENV_FILE)"

logs: check-mode ensure-env
	@$(MAKE) $(MODE)-logs MODE="$(MODE)" ENV_FILE="$(ENV_FILE)"

status: check-mode ensure-env
	@$(MAKE) $(MODE)-status MODE="$(MODE)" ENV_FILE="$(ENV_FILE)"

ps: status

docker-up: ensure-env ensure-vault
	@bash "$(MAKEFILE_DIR)/scripts/bootstrap.sh" "$(ENV_FILE)"

docker-down: ensure-env
	@$(DOCKER_COMPOSE) down

docker-logs: ensure-env
	@$(DOCKER_COMPOSE) logs -f --tail=100

docker-status: ensure-env
	@$(DOCKER_COMPOSE) ps

bare-up: docker-up

bare-down: docker-down

bare-logs: docker-logs

bare-status: docker-status

clean:
	@$(MAKE) down MODE=docker ENV_FILE="$(ENV_FILE)" >/dev/null 2>&1 || true
	@echo "Stopped Zammad containers. Data volumes and $(ENV_FILE) are preserved."

distclean:
	@$(DOCKER_COMPOSE) down --remove-orphans --volumes >/dev/null 2>&1 || true
	@rm -f "$(ENV_FILE)"
	@echo "Removed Zammad containers, volumes, and generated $(ENV_FILE)."
