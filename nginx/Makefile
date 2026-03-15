SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)
include $(MAKEFILE_DIR)/../scripts/lib/common.mk

NGINX_HTTP_PORT   ?= 80
NGINX_HTTPS_PORT  ?= 443
PROD_HTTP_PORT    ?= 8081
DEV_HTTP_PORT     ?= 8082
API_PORT          ?= 8000
GITEA_HTTP_PORT   ?= 3000
GITLAB_HTTP_PORT  ?= 8929
NEXUS_HTTP_PORT   ?= 8083
VAULT_PORT        ?= 8200

MODE ?= docker
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml

export NGINX_HTTP_PORT PROD_HTTP_PORT DEV_HTTP_PORT API_PORT GITEA_HTTP_PORT GITLAB_HTTP_PORT NEXUS_HTTP_PORT VAULT_PORT

.PHONY: help up down restart logs status clean distclean check-mode check-port-conflict

check-port-conflict:
	@if [[ "$(MODE)" == "docker" && "$(NGINX_HTTP_PORT)" == "80" ]]; then \
		traefik_ids="$$(docker ps --filter "name=svclb-traefik" --format '{{.ID}}')"; \
		if [[ -n "$$traefik_ids" ]]; then \
			for cid in $$traefik_ids; do \
				if docker inspect "$$cid" --format '{{json .HostConfig.PortBindings}}' | grep -Eq '"80/tcp":\[[^]]*"HostPort":"80"'; then \
					echo "Port 80 is already claimed by Kubernetes Traefik (container $$cid)."; \
					echo "Disable Rancher Desktop Kubernetes/Traefik or set NGINX_HTTP_PORT to a different host port."; \
					exit 1; \
				fi; \
			done; \
		fi; \
	fi

up: check-mode check-port-conflict
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

clean:
	@echo "nginx keeps no local generated artifacts; nothing to clean."

distclean: clean

help:
	@echo "Usage:"
	@echo "  make up MODE=docker|bare"
	@echo "  make down MODE=docker|bare"
	@echo "  make logs MODE=docker|bare"
	@echo "  make status MODE=docker|bare"
	@echo "  make distclean"
	@echo ""
	@echo "Notes:"
	@echo "  - MODE=docker starts the nginx reverse proxy on http://localhost:80"
	@echo "  - MODE=bare is a no-op for this service"
	@echo "  - distclean is a no-op because nginx keeps no local generated state"
