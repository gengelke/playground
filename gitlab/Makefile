MODE ?= docker
ENV_FILE ?= .env
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
VAULT_DIR ?= $(abspath $(MAKEFILE_DIR)/../vault)
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)

GITLAB_HTTP_PORT ?= 8929
GITLAB_SSH_PORT ?= 2224
GITLAB_EXTERNAL_URL ?= http://localhost:$(GITLAB_HTTP_PORT)
VAULT_ADDR ?= http://127.0.0.1:8200

DOCKER_COMPOSE := docker compose --env-file $(ENV_FILE) -f docker/docker-compose.yml
BARE_DIR := bare

export GITLAB_HTTP_PORT GITLAB_SSH_PORT GITLAB_EXTERNAL_URL

.PHONY: help up down restart status logs docker-up docker-down docker-status docker-logs docker-register-runners bare-up bare-down bare-status bare-logs validate-mode ensure-env ensure-vault

help:
	@echo "Usage: make <target> MODE=docker|bare"
	@echo ""
	@echo "Targets:"
	@echo "  up      Start GitLab CE and 2 workers"
	@echo "  down    Stop all services"
	@echo "  restart Restart all services"
	@echo "  status  Show service status"
	@echo "  logs    Tail logs"
	@echo ""
	@echo "Examples:"
	@echo "  make up MODE=docker"
	@echo "  make up MODE=bare"

validate-mode:
	@if [ "$(MODE)" != "docker" ] && [ "$(MODE)" != "bare" ]; then \
		echo "Invalid MODE='$(MODE)'. Use MODE=docker or MODE=bare."; \
		exit 1; \
	fi

ensure-env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "No $(ENV_FILE) found. Copying .env.example -> $(ENV_FILE)"; \
		cp .env.example $(ENV_FILE); \
	fi

ensure-vault: validate-mode
	@set -e; \
	http_code="$$(curl -s -o /dev/null -w "%{http_code}" "$(VAULT_ADDR)/v1/sys/health" 2>/dev/null || true)"; \
	if [ -n "$$http_code" ] && [ "$$http_code" != "000" ]; then \
		echo "Vault reachable at $(VAULT_ADDR) (HTTP $$http_code)"; \
	else \
		echo "Vault not reachable at $(VAULT_ADDR); starting $(VAULT_DIR) (MODE=$(MODE))"; \
		$(MAKE) -C "$(VAULT_DIR)" up MODE="$(MODE)"; \
	fi

up: validate-mode ensure-env
ifeq ($(MODE),docker)
	@$(MAKE) docker-up ENV_FILE=$(ENV_FILE)
else
	@$(MAKE) bare-up ENV_FILE=$(ENV_FILE)
endif

down: validate-mode ensure-env
ifeq ($(MODE),docker)
	@$(MAKE) docker-down ENV_FILE=$(ENV_FILE)
else
	@$(MAKE) bare-down ENV_FILE=$(ENV_FILE)
endif

restart: down up

status: validate-mode ensure-env
ifeq ($(MODE),docker)
	@$(MAKE) docker-status ENV_FILE=$(ENV_FILE)
else
	@$(MAKE) bare-status ENV_FILE=$(ENV_FILE)
endif

logs: validate-mode ensure-env
ifeq ($(MODE),docker)
	@$(MAKE) docker-logs ENV_FILE=$(ENV_FILE)
else
	@$(MAKE) bare-logs ENV_FILE=$(ENV_FILE)
endif

docker-up: ensure-env ensure-vault
	@bash docker/bootstrap.sh $(ENV_FILE)

docker-down: ensure-env
	@$(DOCKER_COMPOSE) down

docker-status: ensure-env
	@$(DOCKER_COMPOSE) ps

docker-logs: ensure-env
	@$(DOCKER_COMPOSE) logs -f --tail=100

docker-register-runners: ensure-env
	@$(DOCKER_COMPOSE) exec gitlab-runner-1 /bin/sh /register-runner.sh
	@$(DOCKER_COMPOSE) exec gitlab-runner-2 /bin/sh /register-runner.sh

bare-up: ensure-env ensure-vault
	@bash $(BARE_DIR)/up.sh $(ENV_FILE)

bare-down: ensure-env
	@bash $(BARE_DIR)/down.sh $(ENV_FILE)

bare-status: ensure-env
	@bash $(BARE_DIR)/status.sh $(ENV_FILE)

bare-logs: ensure-env
	@bash $(BARE_DIR)/logs.sh $(ENV_FILE)
