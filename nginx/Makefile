SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)
include $(MAKEFILE_DIR)/../scripts/lib/common.mk

MODE ?= docker
COMPOSE_CMD ?= docker compose
NGINX_HTTPS_PORT ?= 8443
NGINX_URL ?= https://localhost:$(NGINX_HTTPS_PORT)

STATE_DIR ?= .state
TLS_DIR ?= $(STATE_DIR)/tls
CERT_FILE ?= $(TLS_DIR)/playground-nginx.crt
KEY_FILE ?= $(TLS_DIR)/playground-nginx.key
BARE_DIR ?= $(STATE_DIR)/bare
BARE_CONF ?= $(BARE_DIR)/nginx.conf
BARE_PID_FILE ?= $(BARE_DIR)/nginx.pid
BARE_LOG_DIR ?= $(BARE_DIR)/logs

export NGINX_HTTPS_PORT

.PHONY: help up down restart logs status clean distclean cert \
	docker-up docker-down docker-logs docker-status \
	bare-up bare-down bare-logs bare-status

help:
	@printf "%s\n" \
		"nginx HTTPS static site" \
		"" \
		"Usage:" \
		"  make up MODE=docker|bare" \
		"  make down MODE=docker|bare" \
		"  make logs MODE=docker|bare" \
		"  make status MODE=docker|bare" \
		"" \
		"Configurable vars:" \
		"  NGINX_HTTPS_PORT=$(NGINX_HTTPS_PORT)" \
		"  NGINX_URL=$(NGINX_URL)" \
		"  CERT_FILE=$(CERT_FILE)" \
		"  KEY_FILE=$(KEY_FILE)"

up: check-mode
	@$(MAKE) $(MODE)-up

down: check-mode
	@$(MAKE) $(MODE)-down

restart:
	@$(MAKE) down MODE="$(MODE)"
	@$(MAKE) up MODE="$(MODE)"

logs: check-mode
	@$(MAKE) $(MODE)-logs

status: check-mode
	@$(MAKE) $(MODE)-status

cert:
	@command -v openssl >/dev/null 2>&1 || { echo "openssl is required to generate the nginx HTTPS certificate"; exit 1; }
	@mkdir -p "$(TLS_DIR)"
	@if [[ ! -f "$(CERT_FILE)" || ! -f "$(KEY_FILE)" ]]; then \
		openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
			-keyout "$(KEY_FILE)" \
			-out "$(CERT_FILE)" \
			-subj "/CN=localhost" \
			-addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1; \
		chmod 600 "$(KEY_FILE)"; \
		echo "Generated self-signed certificate: $(CERT_FILE)"; \
	fi

docker-up: cert
	@$(COMPOSE_CMD) up -d
	@echo "nginx URL: $(NGINX_URL)"

docker-down:
	@$(COMPOSE_CMD) down

docker-logs:
	@$(COMPOSE_CMD) logs -f --tail=100 nginx

docker-status:
	@$(COMPOSE_CMD) ps

bare-up: cert
	@command -v nginx >/dev/null 2>&1 || { echo "nginx binary is required for MODE=bare"; exit 1; }
	@mkdir -p "$(BARE_DIR)" "$(BARE_LOG_DIR)"
	@sed \
		-e 's|@@HTTPS_PORT@@|$(NGINX_HTTPS_PORT)|g' \
		-e 's|@@WWW_DIR@@|$(abspath www)|g' \
		-e 's|@@CERT_FILE@@|$(abspath $(CERT_FILE))|g' \
		-e 's|@@KEY_FILE@@|$(abspath $(KEY_FILE))|g' \
		-e 's|@@PID_FILE@@|$(abspath $(BARE_PID_FILE))|g' \
		-e 's|@@ACCESS_LOG@@|$(abspath $(BARE_LOG_DIR))/access.log|g' \
		-e 's|@@ERROR_LOG@@|$(abspath $(BARE_LOG_DIR))/error.log|g' \
		config/nginx-bare.conf.template >"$(BARE_CONF)"
	@if [[ -f "$(BARE_PID_FILE)" ]] && kill -0 "$$(cat "$(BARE_PID_FILE)")" 2>/dev/null; then \
		echo "nginx already running with PID $$(cat "$(BARE_PID_FILE)")"; \
	else \
		nginx -c "$(abspath $(BARE_CONF))" -p "$(abspath $(BARE_DIR))"; \
		echo "nginx URL: $(NGINX_URL)"; \
	fi

bare-down:
	@if [[ -f "$(BARE_PID_FILE)" ]] && kill -0 "$$(cat "$(BARE_PID_FILE)")" 2>/dev/null; then \
		nginx -s quit -c "$(abspath $(BARE_CONF))" -p "$(abspath $(BARE_DIR))" >/dev/null 2>&1 || kill "$$(cat "$(BARE_PID_FILE)")"; \
		rm -f "$(BARE_PID_FILE)"; \
		echo "nginx stopped"; \
	else \
		echo "nginx is not running"; \
	fi

bare-logs:
	@mkdir -p "$(BARE_LOG_DIR)"
	@touch "$(BARE_LOG_DIR)/access.log" "$(BARE_LOG_DIR)/error.log"
	@tail -f "$(BARE_LOG_DIR)/access.log" "$(BARE_LOG_DIR)/error.log"

bare-status:
	@if [[ -f "$(BARE_PID_FILE)" ]] && kill -0 "$$(cat "$(BARE_PID_FILE)")" 2>/dev/null; then \
		echo "nginx running with PID $$(cat "$(BARE_PID_FILE)")"; \
		echo "nginx URL: $(NGINX_URL)"; \
	else \
		echo "nginx is not running"; \
	fi

clean:
	@$(MAKE) down MODE=docker >/dev/null 2>&1 || true
	@$(MAKE) down MODE=bare >/dev/null 2>&1 || true
	@rm -rf "$(STATE_DIR)"

distclean: clean
