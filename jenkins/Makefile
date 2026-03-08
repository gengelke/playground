SHELL := /usr/bin/env bash

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
VAULT_DIR ?= $(abspath $(MAKEFILE_DIR)/../vault)
PORTS_FILE ?= $(abspath $(MAKEFILE_DIR)/../ports.env)
-include $(PORTS_FILE)

MODE ?= docker
COMPOSE_CMD ?= docker compose
VAULT_ADDR ?= http://127.0.0.1:8200

PIPELINE_REPO_URL ?=
PROD_BRANCH ?= main
DEV_BRANCH ?= dev
PIPELINE_SCRIPT_PATH ?= Jenkinsfile
PIPELINE_JOB_NAME ?= example-pipeline
PIPELINE_AUTH_TOKEN ?= example-pipeline-auth-token
AGENT_COUNT ?= 2
AGENT_EXECUTORS ?= 1
JENKINS_ADMIN_USER ?= admin
JENKINS_ADMIN_PASSWORD ?= password
JENKINS_REGULAR_USER ?= user
JENKINS_REGULAR_PASSWORD ?= password
JENKINS_REGULAR_API_TOKEN_NAME ?= jenkins-api-token

PROD_HTTP_PORT ?= 8081
DEV_HTTP_PORT ?= 8082

STATE_DIR ?= .state

export PIPELINE_REPO_URL PROD_BRANCH DEV_BRANCH PIPELINE_SCRIPT_PATH PIPELINE_JOB_NAME PIPELINE_AUTH_TOKEN
export AGENT_COUNT AGENT_EXECUTORS PROD_HTTP_PORT DEV_HTTP_PORT
export JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD JENKINS_REGULAR_USER JENKINS_REGULAR_PASSWORD
export JENKINS_REGULAR_API_TOKEN_NAME STATE_DIR

.PHONY: help up down restart logs status clean \
	docker-up docker-down docker-logs docker-status docker-clean \
	bare-setup bare-up bare-down bare-logs bare-status bare-clean \
	ensure-vault

.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make up MODE=docker|bare"
	@echo "  make down MODE=docker|bare"
	@echo "  make logs MODE=docker|bare"
	@echo "  make status MODE=docker|bare"
	@echo "  make restart MODE=docker|bare"
	@echo "  make docker-up|docker-down|docker-logs|docker-status|docker-clean"
	@echo "  make bare-setup|bare-up|bare-down|bare-logs|bare-status|bare-clean"
	@echo ""
	@echo "Key variables:"
	@echo "  PIPELINE_REPO_URL=$(if $(PIPELINE_REPO_URL),$(PIPELINE_REPO_URL),<auto repo-a>)"
	@echo "  PROD_BRANCH=$(PROD_BRANCH), DEV_BRANCH=$(DEV_BRANCH)"
	@echo "  PIPELINE_SCRIPT_PATH=$(PIPELINE_SCRIPT_PATH), PIPELINE_JOB_NAME=$(PIPELINE_JOB_NAME)"
	@echo "  PIPELINE_AUTH_TOKEN=$(PIPELINE_AUTH_TOKEN)"
	@echo "  AGENT_COUNT=$(AGENT_COUNT), AGENT_EXECUTORS=$(AGENT_EXECUTORS)"
	@echo "  PROD_HTTP_PORT=$(PROD_HTTP_PORT), DEV_HTTP_PORT=$(DEV_HTTP_PORT)"
	@echo "  JENKINS_ADMIN_USER=$(JENKINS_ADMIN_USER)"
	@echo "  JENKINS_REGULAR_USER=$(JENKINS_REGULAR_USER)"
	@echo "  JENKINS_REGULAR_API_TOKEN_NAME=$(JENKINS_REGULAR_API_TOKEN_NAME)"

up:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) docker-up; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		$(MAKE) bare-up; \
	else \
		echo "Invalid MODE=$(MODE). Use docker or bare."; exit 1; \
	fi

down:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) docker-down; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		$(MAKE) bare-down; \
	else \
		echo "Invalid MODE=$(MODE). Use docker or bare."; exit 1; \
	fi

logs:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) docker-logs; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		$(MAKE) bare-logs; \
	else \
		echo "Invalid MODE=$(MODE). Use docker or bare."; exit 1; \
	fi

status:
	@if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) docker-status; \
	elif [[ "$(MODE)" == "bare" ]]; then \
		$(MAKE) bare-status; \
	else \
		echo "Invalid MODE=$(MODE). Use docker or bare."; exit 1; \
	fi

restart:
	@$(MAKE) down MODE=$(MODE)
	@$(MAKE) up MODE=$(MODE)

ensure-vault:
	@set -euo pipefail; \
	http_code="$$(curl -s -o /dev/null -w "%{http_code}" "$(VAULT_ADDR)/v1/sys/health" 2>/dev/null || true)"; \
	if [[ -n "$$http_code" && "$$http_code" != "000" ]]; then \
		echo "Vault reachable at $(VAULT_ADDR) (HTTP $$http_code)"; \
	else \
		echo "Vault not reachable at $(VAULT_ADDR); starting $(VAULT_DIR) (MODE=$(MODE))"; \
		$(MAKE) -C "$(VAULT_DIR)" up MODE="$(MODE)"; \
	fi

docker-up: ensure-vault
	@set -euo pipefail; \
	source scripts/lib/env.sh; \
	ensure_admin_credentials; \
	repo_url="$$(resolve_pipeline_repo_url docker)"; \
	mkdir -p $(STATE_DIR)/docker/jenkins-prod $(STATE_DIR)/docker/jenkins-dev; \
	mkdir -p $(STATE_DIR)/docker/jenkins-prod/init.groovy.d $(STATE_DIR)/docker/jenkins-dev/init.groovy.d; \
	mkdir -p $(STATE_DIR)/docker/jenkins-prod-agent-1 $(STATE_DIR)/docker/jenkins-prod-agent-2; \
	mkdir -p $(STATE_DIR)/docker/jenkins-dev-agent-1 $(STATE_DIR)/docker/jenkins-dev-agent-2; \
	mkdir -p $(STATE_DIR)/repo-a; \
	cp jenkins/controller/init.groovy.d/00-bootstrap.groovy $(STATE_DIR)/docker/jenkins-prod/init.groovy.d/00-bootstrap.groovy; \
	cp jenkins/controller/init.groovy.d/00-bootstrap.groovy $(STATE_DIR)/docker/jenkins-dev/init.groovy.d/00-bootstrap.groovy; \
	PIPELINE_REPO_URL="$$repo_url" \
	JENKINS_ADMIN_USER="$$JENKINS_ADMIN_USER" \
	JENKINS_ADMIN_PASSWORD="$$JENKINS_ADMIN_PASSWORD" \
	$(COMPOSE_CMD) up -d --build; \
	print_admin_credentials; \
	print_pipeline_configuration "$$repo_url"; \
	print_instance_urls; \
	bash scripts/sync-regular-user-api-tokens.sh

docker-down:
	@$(COMPOSE_CMD) down

docker-logs:
	@$(COMPOSE_CMD) logs -f --tail=200

docker-status:
	@$(COMPOSE_CMD) ps

docker-clean: docker-down
	@rm -rf $(STATE_DIR)/docker

bare-setup:
	@bash scripts/bare/setup.sh

bare-up: ensure-vault bare-setup
	@bash scripts/bare/up.sh

bare-down:
	@bash scripts/bare/down.sh

bare-logs:
	@bash scripts/bare/logs.sh "${TARGET:-all}"

bare-status:
	@bash scripts/bare/status.sh

bare-clean: bare-down
	@rm -rf $(STATE_DIR)/bare $(STATE_DIR)/cache

clean: docker-clean bare-clean
