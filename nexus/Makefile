SHELL := /usr/bin/env bash

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
VAULT_DIR ?= $(abspath $(MAKEFILE_DIR)/../vault)
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)

MODE ?= docker
VAULT_ADDR ?= http://127.0.0.1:8200

NEXUS_VERSION ?= 3.70.1-02
NEXUS_DIST_URL ?= https://download.sonatype.com/nexus/3/nexus-$(NEXUS_VERSION)-unix.tar.gz
NEXUS_BASE_DIR ?= $(CURDIR)/.local
NEXUS_DATA_DIR ?= $(CURDIR)/data/bare-data
NEXUS_LOG_FILE ?= $(CURDIR)/logs/bare/nexus.log
NEXUS_PID_FILE ?= $(CURDIR)/run/nexus.pid
NEXUS_BOOTSTRAP_USER ?= admin
NEXUS_BOOTSTRAP_PASSWORD ?=
NEXUS_ADMIN_USER ?= admin
NEXUS_ADMIN_PASSWORD ?= password
NEXUS_REGULAR_USER ?= user
NEXUS_REGULAR_PASSWORD ?= password
NEXUS_ANONYMOUS_ENABLED ?= false
NEXUS_AUTO_INIT ?= true
NEXUS_WAIT_TIMEOUT ?= 600
NEXUS_WAIT_INTERVAL ?= 5
NEXUS_CONNECT_TIMEOUT ?= 2
NEXUS_CURL_MAX_TIME ?= 5
NEXUS_DOCKER_PORT_FILE ?= $(CURDIR)/run/docker.port

DOCKER_DATA_DIR ?= $(CURDIR)/data/docker-data
DOCKER_COMPOSE ?= docker compose
NEXUS_HTTP_PORT ?= 8083

.PHONY: up down restart logs status clean help ensure-vault

help:
	@echo "Usage:"
	@echo "  make up MODE=docker|bare"
	@echo "  make down MODE=docker|bare"
	@echo "  make logs MODE=docker|bare"
	@echo "  make status MODE=docker|bare"
	@echo "  make restart MODE=docker|bare"
	@echo
	@echo "Configurable vars:"
	@echo "  MODE            (default: docker)"
	@echo "  NEXUS_VERSION   (default: $(NEXUS_VERSION))"
	@echo "  NEXUS_DIST_URL  (default derived from version)"
	@echo "  NEXUS_HTTP_PORT (host/bare port, default: $(NEXUS_HTTP_PORT))"
	@echo "  NEXUS_BOOTSTRAP_USER (default: $(NEXUS_BOOTSTRAP_USER))"
	@echo "  NEXUS_BOOTSTRAP_PASSWORD (default: NEXUS_ADMIN_PASSWORD)"
	@echo "  NEXUS_ADMIN_USER (default: $(NEXUS_ADMIN_USER))"
	@echo "  NEXUS_ADMIN_PASSWORD (default: $(NEXUS_ADMIN_PASSWORD))"
	@echo "  NEXUS_REGULAR_USER (default: $(NEXUS_REGULAR_USER))"
	@echo "  NEXUS_REGULAR_PASSWORD (default: $(NEXUS_REGULAR_PASSWORD))"
	@echo "  NEXUS_ANONYMOUS_ENABLED (default: $(NEXUS_ANONYMOUS_ENABLED))"
	@echo "  NEXUS_AUTO_INIT (default: $(NEXUS_AUTO_INIT))"
	@echo "  NEXUS_WAIT_TIMEOUT (default: $(NEXUS_WAIT_TIMEOUT)s)"
	@echo "  NEXUS_WAIT_INTERVAL (default: $(NEXUS_WAIT_INTERVAL)s)"
	@echo "  NEXUS_CONNECT_TIMEOUT (default: $(NEXUS_CONNECT_TIMEOUT)s)"
	@echo "  NEXUS_CURL_MAX_TIME (default: $(NEXUS_CURL_MAX_TIME)s)"
	@echo "  NEXUS_DOCKER_PORT_FILE (default: $(NEXUS_DOCKER_PORT_FILE))"

ensure-vault:
	@set -euo pipefail; \
	http_code="$$(curl -s -o /dev/null -w "%{http_code}" "$(VAULT_ADDR)/v1/sys/health" 2>/dev/null || true)"; \
	if [[ -n "$$http_code" && "$$http_code" != "000" ]]; then \
		echo "Vault reachable at $(VAULT_ADDR) (HTTP $$http_code)"; \
	else \
		echo "Vault not reachable at $(VAULT_ADDR); starting $(VAULT_DIR) (MODE=$(MODE))"; \
		$(MAKE) -C "$(VAULT_DIR)" up MODE="$(MODE)"; \
	fi

up: ensure-vault
ifeq ($(MODE),docker)
	@mkdir -p "$(DOCKER_DATA_DIR)" "$(dir $(NEXUS_DOCKER_PORT_FILE))"
	@resolved_port="$$(./scripts/resolve-http-port.sh "$(NEXUS_HTTP_PORT)")"; \
	echo "$$resolved_port" >"$(NEXUS_DOCKER_PORT_FILE)"; \
	echo "Using Docker Nexus host port: $$resolved_port"; \
	echo "Nexus URL: http://localhost:$$resolved_port"; \
	NEXUS_HTTP_PORT="$$resolved_port" $(DOCKER_COMPOSE) up -d
ifeq ($(NEXUS_AUTO_INIT),true)
	@resolved_port="$$(cat "$(NEXUS_DOCKER_PORT_FILE)")"; \
	NEXUS_URL="http://localhost:$$resolved_port" \
	NEXUS_DATA_DIR="$(DOCKER_DATA_DIR)" \
	NEXUS_BOOTSTRAP_USER="$(NEXUS_BOOTSTRAP_USER)" \
	NEXUS_BOOTSTRAP_PASSWORD="$(NEXUS_BOOTSTRAP_PASSWORD)" \
	NEXUS_ADMIN_USER="$(NEXUS_ADMIN_USER)" \
	NEXUS_ADMIN_PASSWORD="$(NEXUS_ADMIN_PASSWORD)" \
	NEXUS_REGULAR_USER="$(NEXUS_REGULAR_USER)" \
	NEXUS_REGULAR_PASSWORD="$(NEXUS_REGULAR_PASSWORD)" \
	NEXUS_ANONYMOUS_ENABLED="$(NEXUS_ANONYMOUS_ENABLED)" \
	NEXUS_WAIT_TIMEOUT="$(NEXUS_WAIT_TIMEOUT)" \
	NEXUS_WAIT_INTERVAL="$(NEXUS_WAIT_INTERVAL)" \
	NEXUS_CONNECT_TIMEOUT="$(NEXUS_CONNECT_TIMEOUT)" \
	NEXUS_CURL_MAX_TIME="$(NEXUS_CURL_MAX_TIME)" \
	./scripts/nexus-bootstrap.sh
endif
else ifeq ($(MODE),bare)
	@mkdir -p "$(dir $(NEXUS_LOG_FILE))" "$(dir $(NEXUS_PID_FILE))" "$(NEXUS_DATA_DIR)"
	NEXUS_DIST_URL="$(NEXUS_DIST_URL)" \
	NEXUS_BASE_DIR="$(NEXUS_BASE_DIR)" \
	NEXUS_DATA_DIR="$(NEXUS_DATA_DIR)" \
	NEXUS_LOG_FILE="$(NEXUS_LOG_FILE)" \
	NEXUS_PID_FILE="$(NEXUS_PID_FILE)" \
	NEXUS_HTTP_PORT="$(NEXUS_HTTP_PORT)" \
	./scripts/bare-up.sh
	@echo "Nexus URL: http://localhost:$(NEXUS_HTTP_PORT)"
ifeq ($(NEXUS_AUTO_INIT),true)
	NEXUS_URL="http://localhost:$(NEXUS_HTTP_PORT)" \
	NEXUS_DATA_DIR="$(NEXUS_DATA_DIR)" \
	NEXUS_BOOTSTRAP_USER="$(NEXUS_BOOTSTRAP_USER)" \
	NEXUS_BOOTSTRAP_PASSWORD="$(NEXUS_BOOTSTRAP_PASSWORD)" \
	NEXUS_ADMIN_USER="$(NEXUS_ADMIN_USER)" \
	NEXUS_ADMIN_PASSWORD="$(NEXUS_ADMIN_PASSWORD)" \
	NEXUS_REGULAR_USER="$(NEXUS_REGULAR_USER)" \
	NEXUS_REGULAR_PASSWORD="$(NEXUS_REGULAR_PASSWORD)" \
	NEXUS_ANONYMOUS_ENABLED="$(NEXUS_ANONYMOUS_ENABLED)" \
	NEXUS_WAIT_TIMEOUT="$(NEXUS_WAIT_TIMEOUT)" \
	NEXUS_WAIT_INTERVAL="$(NEXUS_WAIT_INTERVAL)" \
	NEXUS_CONNECT_TIMEOUT="$(NEXUS_CONNECT_TIMEOUT)" \
	NEXUS_CURL_MAX_TIME="$(NEXUS_CURL_MAX_TIME)" \
	./scripts/nexus-bootstrap.sh
endif
else
	$(error Unsupported MODE '$(MODE)'. Use MODE=docker or MODE=bare)
endif

down:
ifeq ($(MODE),docker)
	NEXUS_HTTP_PORT="$(NEXUS_HTTP_PORT)" $(DOCKER_COMPOSE) down
	@rm -f "$(NEXUS_DOCKER_PORT_FILE)"
else ifeq ($(MODE),bare)
	NEXUS_PID_FILE="$(NEXUS_PID_FILE)" ./scripts/bare-down.sh
else
	$(error Unsupported MODE '$(MODE)'. Use MODE=docker or MODE=bare)
endif

restart:
	@$(MAKE) down MODE=$(MODE)
	@$(MAKE) up MODE=$(MODE)

logs:
ifeq ($(MODE),docker)
	NEXUS_HTTP_PORT="$(NEXUS_HTTP_PORT)" $(DOCKER_COMPOSE) logs -f nexus
else ifeq ($(MODE),bare)
	@mkdir -p "$(dir $(NEXUS_LOG_FILE))"
	@touch "$(NEXUS_LOG_FILE)"
	tail -f "$(NEXUS_LOG_FILE)"
else
	$(error Unsupported MODE '$(MODE)'. Use MODE=docker or MODE=bare)
endif

status:
ifeq ($(MODE),docker)
	NEXUS_HTTP_PORT="$(NEXUS_HTTP_PORT)" $(DOCKER_COMPOSE) ps
else ifeq ($(MODE),bare)
	NEXUS_PID_FILE="$(NEXUS_PID_FILE)" ./scripts/bare-status.sh
else
	$(error Unsupported MODE '$(MODE)'. Use MODE=docker or MODE=bare)
endif

clean:
	rm -rf .local data logs run
