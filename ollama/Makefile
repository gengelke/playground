SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= docker
DOCKER_COMPOSE ?= docker compose -f docker-compose.yml
OLLAMA_PORT ?= 11434
OLLAMA_URL ?= http://127.0.0.1:$(OLLAMA_PORT)
OLLAMA_MODEL ?= llama3.1
OLLAMA_IMAGE_TAG ?= latest
OLLAMA_WAIT_SECONDS ?= 60
OLLAMA_DATA_DIR ?= $(MAKEFILE_DIR)data
OLLAMA_NETWORK ?= playground-llm

export OLLAMA_PORT OLLAMA_IMAGE_TAG

.PHONY: help build up down restart logs status ps clean distclean pull-model \
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
	@OLLAMA_PORT="$(OLLAMA_PORT)" OLLAMA_IMAGE_TAG="$(OLLAMA_IMAGE_TAG)" $(DOCKER_COMPOSE) pull ollama

docker-up:
	@mkdir -p "$(OLLAMA_DATA_DIR)"
	@docker network inspect "$(OLLAMA_NETWORK)" >/dev/null 2>&1 || docker network create "$(OLLAMA_NETWORK)" >/dev/null
	@OLLAMA_PORT="$(OLLAMA_PORT)" OLLAMA_IMAGE_TAG="$(OLLAMA_IMAGE_TAG)" $(DOCKER_COMPOSE) up -d
	@for _ in $$(seq 1 "$(OLLAMA_WAIT_SECONDS)"); do \
		if curl -fsS "$(OLLAMA_URL)/api/tags" >/dev/null 2>&1; then \
			echo "Ollama is ready at $(OLLAMA_URL)"; \
			$(MAKE) pull-model MODE=docker OLLAMA_MODEL="$(OLLAMA_MODEL)"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "Ollama did not become ready in time."; \
	$(MAKE) docker-down MODE=docker >/dev/null; \
	exit 1

pull-model:
	@echo "Ensuring Ollama model is available: $(OLLAMA_MODEL)"
	@if $(DOCKER_COMPOSE) exec -T ollama ollama show "$(OLLAMA_MODEL)" >/dev/null 2>&1; then \
		echo "Model $(OLLAMA_MODEL) is already present."; \
	else \
		$(DOCKER_COMPOSE) exec -T ollama ollama pull "$(OLLAMA_MODEL)"; \
	fi

docker-down:
	@OLLAMA_PORT="$(OLLAMA_PORT)" OLLAMA_IMAGE_TAG="$(OLLAMA_IMAGE_TAG)" $(DOCKER_COMPOSE) down

docker-logs:
	@OLLAMA_PORT="$(OLLAMA_PORT)" OLLAMA_IMAGE_TAG="$(OLLAMA_IMAGE_TAG)" $(DOCKER_COMPOSE) logs -f --tail=100 ollama

docker-status:
	@OLLAMA_PORT="$(OLLAMA_PORT)" OLLAMA_IMAGE_TAG="$(OLLAMA_IMAGE_TAG)" $(DOCKER_COMPOSE) ps
	@echo "Configured model: $(OLLAMA_MODEL)"
	@echo "Models are stored on the host at: $(OLLAMA_DATA_DIR)"

bare-build: docker-build

bare-up: docker-up

bare-down: docker-down

bare-logs: docker-logs

bare-status: docker-status

clean:
	@$(MAKE) down MODE=docker >/dev/null 2>&1 || true
	@echo "Stopped Ollama container. Model data is preserved at $(OLLAMA_DATA_DIR)."

distclean: clean
	@OLLAMA_PORT="$(OLLAMA_PORT)" OLLAMA_IMAGE_TAG="$(OLLAMA_IMAGE_TAG)" $(DOCKER_COMPOSE) down --remove-orphans
	@rm -rf "$(OLLAMA_DATA_DIR)"
	@echo "Removed Ollama container and model data."

help:
	@printf "%s\n" \
		"Usage:" \
		"  make up MODE=docker        # start Ollama and pull OLLAMA_MODEL" \
		"  make down MODE=docker      # stop container, keep model data" \
		"  make logs MODE=docker" \
		"  make status MODE=docker" \
		"  make pull-model OLLAMA_MODEL=llama3.1" \
		"  make distclean             # remove container and model data" \
		"  MODE=bare aliases Docker for this service" \
		"" \
		"Key variables:" \
		"  MODE=$(MODE)" \
		"  OLLAMA_PORT=$(OLLAMA_PORT)" \
		"  OLLAMA_URL=$(OLLAMA_URL)" \
		"  OLLAMA_MODEL=$(OLLAMA_MODEL)" \
		"  OLLAMA_DATA_DIR=$(OLLAMA_DATA_DIR)" \
		"  OLLAMA_NETWORK=$(OLLAMA_NETWORK)" \
		"  OLLAMA_IMAGE_TAG=$(OLLAMA_IMAGE_TAG)"
