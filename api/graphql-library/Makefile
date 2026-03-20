SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(MAKEFILE_DIR)/../..)
API_DIR ?= $(abspath $(MAKEFILE_DIR)/..)
FASTAPI_DIR ?= $(API_DIR)/fastapi
PORTS_FILE ?= $(ROOT_DIR)/ports.env
-include $(PORTS_FILE)
include $(ROOT_DIR)/scripts/lib/common.mk

MODE ?= bare
API_PORT ?= 8000
API_URL ?= http://127.0.0.1:$(API_PORT)
PYTHON ?= python3
DOCKER ?= docker
DOCKER_IMAGE ?= playground-graphql-library
DOCKERFILE ?= $(MAKEFILE_DIR)Dockerfile
DOCKER_WORKDIR ?= /workspace/api/graphql-library
DOCKER_API_DIR ?= /workspace/api
BUILD_DIR := $(MAKEFILE_DIR)build
GENERATED_DIR := $(MAKEFILE_DIR)generated
DIST_DIR := $(MAKEFILE_DIR)dist
VENV_DIR ?= $(MAKEFILE_DIR).venv
VENV_PIP := $(VENV_DIR)/bin/pip
VENV_PYTHON := $(VENV_DIR)/bin/python
DEPS_STAMP := $(VENV_DIR)/.deps-installed

SCHEMA_SOURCE ?= $(if $(filter docker,$(MODE)),remote,local)
REMOTE_SCHEMA_URL ?= $(if $(filter docker,$(MODE)),http://host.docker.internal:$(API_PORT)/graphql,$(API_URL)/graphql)
SANITIZE_TLS_ENV = \
	for cert_var in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE PIP_CERT; do \
		cert_path="$${!cert_var:-}"; \
		if [[ -n "$$cert_path" && ! -f "$$cert_path" ]]; then \
			echo "Ignoring invalid $$cert_var=$$cert_path" >&2; \
			unset "$$cert_var"; \
		fi; \
		done;

.PHONY: help venv deps generate clean distclean \
	bare-deps docker-deps bare-generate docker-generate

venv:
	@if [[ ! -x "$(VENV_PIP)" ]]; then \
		rm -rf "$(VENV_DIR)"; \
		"$(PYTHON)" -m venv "$(VENV_DIR)"; \
	fi

$(DEPS_STAMP): requirements.txt | venv
	@$(SANITIZE_TLS_ENV) \
		PIP_DISABLE_PIP_VERSION_CHECK=1 "$(VENV_PYTHON)" -m pip install -r requirements.txt
	@touch "$(DEPS_STAMP)"

deps: check-mode
	@$(MAKE) $(MODE)-deps MODE="$(MODE)" API_PORT="$(API_PORT)"

bare-deps: $(DEPS_STAMP)

docker-deps:
	@$(DOCKER) build -f "$(DOCKERFILE)" -t "$(DOCKER_IMAGE)" "$(API_DIR)"

generate: check-mode
	@$(MAKE) $(MODE)-generate \
		MODE="$(MODE)" \
		API_PORT="$(API_PORT)" \
		SCHEMA_SOURCE="$(SCHEMA_SOURCE)" \
		REMOTE_SCHEMA_URL="$(REMOTE_SCHEMA_URL)"

bare-generate: bare-deps
	@$(SANITIZE_TLS_ENV) \
		if [[ "$(SCHEMA_SOURCE)" == "remote" ]]; then \
			$(MAKE) -C "$(FASTAPI_DIR)" down MODE="docker" >/dev/null 2>&1 || true; \
			$(MAKE) -C "$(FASTAPI_DIR)" up MODE="bare" API_PORT="$(API_PORT)"; \
		fi
	@$(SANITIZE_TLS_ENV) \
		cd "$(MAKEFILE_DIR)" && \
		"$(VENV_PYTHON)" scripts/generate_library.py \
			--schema-source "$(SCHEMA_SOURCE)" \
			--remote-schema-url "$(REMOTE_SCHEMA_URL)"

docker-generate: docker-deps
	@if [[ "$(SCHEMA_SOURCE)" == "remote" ]]; then \
		$(MAKE) -C "$(FASTAPI_DIR)" down MODE="bare" >/dev/null 2>&1 || true; \
		$(MAKE) -C "$(FASTAPI_DIR)" up MODE="docker" API_PORT="$(API_PORT)"; \
	fi
	@$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e FASTAPI_BASIC_AUTH_USERNAME \
		-e FASTAPI_BASIC_AUTH_PASSWORD \
		-v "$(API_DIR):$(DOCKER_API_DIR)" \
		-w "$(DOCKER_WORKDIR)" \
		"$(DOCKER_IMAGE)" \
		python scripts/generate_library.py \
			--schema-source "$(SCHEMA_SOURCE)" \
			--remote-schema-url "$(REMOTE_SCHEMA_URL)"

clean:
	@rm -rf "$(BUILD_DIR)" "$(GENERATED_DIR)"

distclean: clean
	@rm -rf "$(VENV_DIR)" "$(DIST_DIR)"
	@find "$(MAKEFILE_DIR)" -maxdepth 1 -type d -name "*.egg-info" -exec rm -rf {} +

help:
	@printf "%s\n" \
		"Usage:" \
		"  make generate MODE=docker|bare [SCHEMA_SOURCE=local|remote]" \
		"  make deps" \
		"  make clean" \
		"  make distclean" \
		"" \
		"Key variables:" \
		"  MODE=$(MODE)" \
		"  API_PORT=$(API_PORT)" \
		"  DOCKER_IMAGE=$(DOCKER_IMAGE)" \
		"  SCHEMA_SOURCE=$(SCHEMA_SOURCE)" \
		"  REMOTE_SCHEMA_URL=$(REMOTE_SCHEMA_URL)" \
		"" \
		"MODE=docker builds $(DOCKER_IMAGE) and runs the generator inside a container." \
		"MODE=bare uses the local virtualenv and defaults to SCHEMA_SOURCE=local."
