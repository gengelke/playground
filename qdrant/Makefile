SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml
QDRANT_PORT ?= 6333
QDRANT_URL ?= http://127.0.0.1:$(QDRANT_PORT)
QDRANT_IMAGE_TAG ?= v1.12.4
QDRANT_WAIT_SECONDS ?= 60
QDRANT_DATA_DIR ?= $(MAKEFILE_DIR)data
QDRANT_NETWORK ?= playground-vector

export QDRANT_PORT QDRANT_IMAGE_TAG

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
	@QDRANT_PORT="$(QDRANT_PORT)" QDRANT_IMAGE_TAG="$(QDRANT_IMAGE_TAG)" $(DOCKER_COMPOSE) pull qdrant

docker-up:
	@mkdir -p "$(QDRANT_DATA_DIR)"
	@docker network inspect "$(QDRANT_NETWORK)" >/dev/null 2>&1 || docker network create "$(QDRANT_NETWORK)" >/dev/null
	@QDRANT_PORT="$(QDRANT_PORT)" QDRANT_IMAGE_TAG="$(QDRANT_IMAGE_TAG)" $(DOCKER_COMPOSE) up -d
	@for _ in $$(seq 1 "$(QDRANT_WAIT_SECONDS)"); do \
		if curl -fsS "$(QDRANT_URL)/collections" >/dev/null 2>&1; then \
			echo "Qdrant is ready at $(QDRANT_URL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "Qdrant did not become ready in time."; \
	$(MAKE) docker-down MODE=docker >/dev/null; \
	exit 1

docker-down:
	@QDRANT_PORT="$(QDRANT_PORT)" QDRANT_IMAGE_TAG="$(QDRANT_IMAGE_TAG)" $(DOCKER_COMPOSE) down

docker-logs:
	@QDRANT_PORT="$(QDRANT_PORT)" QDRANT_IMAGE_TAG="$(QDRANT_IMAGE_TAG)" $(DOCKER_COMPOSE) logs -f --tail=100 qdrant

docker-status:
	@QDRANT_PORT="$(QDRANT_PORT)" QDRANT_IMAGE_TAG="$(QDRANT_IMAGE_TAG)" $(DOCKER_COMPOSE) ps
	@echo "Qdrant data is stored on the host at: $(QDRANT_DATA_DIR)"

bare-build: docker-build

bare-up: docker-up

bare-down: docker-down

bare-logs: docker-logs

bare-status: docker-status

clean:
	@$(MAKE) down MODE=docker >/dev/null 2>&1 || true
	@echo "Stopped Qdrant container. Vector data is preserved at $(QDRANT_DATA_DIR)."

distclean: clean
	@QDRANT_PORT="$(QDRANT_PORT)" QDRANT_IMAGE_TAG="$(QDRANT_IMAGE_TAG)" $(DOCKER_COMPOSE) down --remove-orphans
	@rm -rf "$(QDRANT_DATA_DIR)"
	@echo "Removed Qdrant container and vector data."

help:
	@printf "%s\n" \
		"Usage:" \
		"  make up MODE=docker        # start Qdrant" \
		"  make down MODE=docker      # stop container, keep vector data" \
		"  make logs MODE=docker" \
		"  make status MODE=docker" \
		"  make distclean             # remove container and vector data" \
		"  MODE=bare aliases Docker for this service" \
		"" \
		"Key variables:" \
		"  MODE=$(MODE)" \
		"  QDRANT_PORT=$(QDRANT_PORT)" \
		"  QDRANT_URL=$(QDRANT_URL)" \
		"  QDRANT_DATA_DIR=$(QDRANT_DATA_DIR)" \
		"  QDRANT_NETWORK=$(QDRANT_NETWORK)" \
		"  QDRANT_IMAGE_TAG=$(QDRANT_IMAGE_TAG)"
