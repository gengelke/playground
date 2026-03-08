SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)

MODE ?= docker
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml

export NGINX_HTTP_PORT PROD_HTTP_PORT DEV_HTTP_PORT API_PORT GITEA_HTTP_PORT GITLAB_HTTP_PORT NEXUS_HTTP_PORT VAULT_PORT

.PHONY: help up down restart logs status check-mode

check-mode:
	@if [[ "$(MODE)" != "docker" && "$(MODE)" != "bare" ]]; then \
		echo "Unsupported MODE='$(MODE)'. Use MODE=docker or MODE=bare."; \
		exit 1; \
	fi

up: check-mode
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(DOCKER_COMPOSE) up -d; \
	else \
		echo "nginx reverse proxy is Docker-only; skipping MODE=bare."; \
	fi

down: check-mode
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(DOCKER_COMPOSE) down; \
	else \
		echo "nginx reverse proxy is Docker-only; skipping MODE=bare."; \
	fi

restart: down up

logs: check-mode
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(DOCKER_COMPOSE) logs -f --tail=100; \
	else \
		echo "nginx reverse proxy is Docker-only; no logs in MODE=bare."; \
	fi

status: check-mode
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(DOCKER_COMPOSE) ps; \
	else \
		echo "nginx reverse proxy is Docker-only; no status in MODE=bare."; \
	fi

help:
	@echo "Usage:"
	@echo "  make up MODE=docker|bare"
	@echo "  make down MODE=docker|bare"
	@echo "  make logs MODE=docker|bare"
	@echo "  make status MODE=docker|bare"
	@echo ""
	@echo "Notes:"
	@echo "  - MODE=docker starts the nginx reverse proxy on http://localhost:80"
	@echo "  - MODE=bare is a no-op for this service"
