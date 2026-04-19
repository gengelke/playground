SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml
N8N_PORT ?= 5678
N8N_URL ?= http://127.0.0.1:$(N8N_PORT)
N8N_IMAGE_TAG ?= latest
N8N_RUNNERS_IMAGE_TAG ?= latest
N8N_RUNNERS_BROKER_PORT ?= 5679
N8N_RUNNERS_AUTH_TOKEN ?= playground-runner-secret
N8N_WAIT_SECONDS ?= 60
N8N_NETWORK ?= playground-vector
N8N_LOCAL_FILES_DIR ?= $(MAKEFILE_DIR)local-files

export N8N_PORT N8N_IMAGE_TAG N8N_RUNNERS_IMAGE_TAG N8N_RUNNERS_BROKER_PORT N8N_RUNNERS_AUTH_TOKEN

.PHONY: help build up down restart logs status ps clean distclean \
	check-mode docker-build docker-up docker-down docker-logs docker-status \
	bare-build bare-up bare-down bare-logs bare-status

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

ps: status

docker-build:
	@$(DOCKER_COMPOSE) pull

docker-up:
	@mkdir -p "$(N8N_LOCAL_FILES_DIR)"
	@docker network inspect "$(N8N_NETWORK)" >/dev/null 2>&1 || docker network create "$(N8N_NETWORK)" >/dev/null
	@$(DOCKER_COMPOSE) up -d
	@for _ in $$(seq 1 "$(N8N_WAIT_SECONDS)"); do \
		if curl -fsS "$(N8N_URL)/healthz" >/dev/null 2>&1; then \
			echo "n8n is ready at $(N8N_URL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "n8n did not become ready in time."; \
	$(MAKE) docker-down MODE=docker >/dev/null; \
	exit 1

docker-down:
	@$(DOCKER_COMPOSE) down

docker-logs:
	@$(DOCKER_COMPOSE) logs -f --tail=100

docker-status:
	@$(DOCKER_COMPOSE) ps

bare-build: docker-build

bare-up: docker-up

bare-down: docker-down

bare-logs: docker-logs

bare-status: docker-status

clean:
	@$(MAKE) down MODE=docker >/dev/null 2>&1 || true
	@echo "Stopped n8n containers. Workflow data is preserved in the n8n-data volume."

distclean: clean
	@$(DOCKER_COMPOSE) down --remove-orphans --volumes
	@echo "Removed n8n containers and workflow data volume."

help:
	@printf "%s\n" \
		"Usage:" \
		"  make up MODE=docker        # start n8n + task-runner" \
		"  make down MODE=docker      # stop containers, keep workflow data" \
		"  make logs MODE=docker      # tail logs from both containers" \
		"  make status MODE=docker" \
		"  make distclean             # remove containers and workflow data volume" \
		"  MODE=bare aliases Docker for this service" \
		"" \
		"Key variables:" \
		"  MODE=$(MODE)" \
		"  N8N_PORT=$(N8N_PORT)" \
		"  N8N_URL=$(N8N_URL)" \
		"  N8N_IMAGE_TAG=$(N8N_IMAGE_TAG)" \
		"  N8N_RUNNERS_IMAGE_TAG=$(N8N_RUNNERS_IMAGE_TAG)" \
		"  N8N_RUNNERS_AUTH_TOKEN=$(N8N_RUNNERS_AUTH_TOKEN)" \
		"  N8N_LOCAL_FILES_DIR=$(N8N_LOCAL_FILES_DIR)" \
		"" \
		"Inside workflows, Qdrant is reachable at: http://playground-qdrant:6333" \
		"Local file exchange with containers:      $(N8N_LOCAL_FILES_DIR) -> /files"
