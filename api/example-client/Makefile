SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR := $(abspath $(MAKEFILE_DIR)/..)
TOPLEVEL_DIR := $(abspath $(ROOT_DIR)/..)
GRAPHQL_LIBRARY_DIR := $(ROOT_DIR)/graphql-library
GRAPHQL_LIBRARY_VENV_PYTHON := $(GRAPHQL_LIBRARY_DIR)/.venv/bin/python
GRAPHQL_LIBRARY_GENERATED_DIR := $(GRAPHQL_LIBRARY_DIR)/generated
include $(TOPLEVEL_DIR)/scripts/lib/common.mk

MODE ?= bare
API_PORT ?= 8000
DOCKER ?= docker
DOCKER_IMAGE ?= playground-graphql-library
DOCKER_WORKDIR ?= /workspace/api/example-client
DOCKER_API_DIR ?= /workspace/api
DEFAULT_GRAPHQL_URL := http://127.0.0.1:8000/graphql
DEFAULT_DOCKER_GRAPHQL_URL := http://host.docker.internal:$(API_PORT)/graphql
GRAPHQL_URL ?= $(if $(filter docker,$(MODE)),$(DEFAULT_DOCKER_GRAPHQL_URL),$(DEFAULT_GRAPHQL_URL))
EMPLOYEE_ID ?=
EMPLOYEE_NAME ?=
EMPLOYEE_SURNAME ?=
EMPLOYEE_ROLE ?=
UPDATED_EMPLOYEE_NAME ?=
UPDATED_EMPLOYEE_SURNAME ?=
UPDATED_EMPLOYEE_ROLE ?=

.PHONY: help run run-local clean distclean bare-run docker-run

run:
	@$(MAKE) check-mode MODE="$(MODE)"
	@$(MAKE) $(MODE)-run \
		MODE="$(MODE)" \
		API_PORT="$(API_PORT)" \
		GRAPHQL_URL="$(GRAPHQL_URL)" \
		EMPLOYEE_ID="$(EMPLOYEE_ID)" \
		EMPLOYEE_NAME="$(EMPLOYEE_NAME)" \
		EMPLOYEE_SURNAME="$(EMPLOYEE_SURNAME)" \
		EMPLOYEE_ROLE="$(EMPLOYEE_ROLE)" \
		UPDATED_EMPLOYEE_NAME="$(UPDATED_EMPLOYEE_NAME)" \
		UPDATED_EMPLOYEE_SURNAME="$(UPDATED_EMPLOYEE_SURNAME)" \
		UPDATED_EMPLOYEE_ROLE="$(UPDATED_EMPLOYEE_ROLE)"

bare-run:
	@if [[ ! -x "$(GRAPHQL_LIBRARY_VENV_PYTHON)" ]]; then \
		$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" generate MODE="bare" API_PORT="$(API_PORT)"; \
	fi
	@if [[ ! -d "$(GRAPHQL_LIBRARY_GENERATED_DIR)/fastapi_graphql_client" ]]; then \
		$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" generate MODE="bare" API_PORT="$(API_PORT)"; \
	fi
	@cd "$(MAKEFILE_DIR)" && \
		PYTHONPATH="$(GRAPHQL_LIBRARY_GENERATED_DIR)${PYTHONPATH:+:$$PYTHONPATH}" \
		"$(GRAPHQL_LIBRARY_VENV_PYTHON)" company.py \
			--graphql-url "$(GRAPHQL_URL)" \
			workflow \
			$(if $(EMPLOYEE_ID),--employee-id "$(EMPLOYEE_ID)",) \
			$(if $(EMPLOYEE_NAME),--employee-name "$(EMPLOYEE_NAME)",) \
			$(if $(EMPLOYEE_SURNAME),--employee-surname "$(EMPLOYEE_SURNAME)",) \
			$(if $(EMPLOYEE_ROLE),--employee-role "$(EMPLOYEE_ROLE)",) \
			$(if $(UPDATED_EMPLOYEE_NAME),--updated-employee-name "$(UPDATED_EMPLOYEE_NAME)",) \
			$(if $(UPDATED_EMPLOYEE_SURNAME),--updated-employee-surname "$(UPDATED_EMPLOYEE_SURNAME)",) \
			$(if $(UPDATED_EMPLOYEE_ROLE),--updated-employee-role "$(UPDATED_EMPLOYEE_ROLE)",)

docker-run:
	@if [[ ! -d "$(GRAPHQL_LIBRARY_GENERATED_DIR)/fastapi_graphql_client" ]]; then \
		$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" generate MODE="docker" API_PORT="$(API_PORT)"; \
	fi
	@$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" docker-deps MODE="docker" API_PORT="$(API_PORT)"
	@$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e FASTAPI_BASIC_AUTH_USERNAME \
		-e FASTAPI_BASIC_AUTH_PASSWORD \
		-v "$(ROOT_DIR):$(DOCKER_API_DIR)" \
		-w "$(DOCKER_WORKDIR)" \
		"$(DOCKER_IMAGE)" \
		env FORCE_COLOR=1 PYTHONPATH="$(DOCKER_API_DIR)/graphql-library/generated" \
		python company.py \
			--graphql-url "$(GRAPHQL_URL)" \
			workflow \
			$(if $(EMPLOYEE_ID),--employee-id "$(EMPLOYEE_ID)",) \
			$(if $(EMPLOYEE_NAME),--employee-name "$(EMPLOYEE_NAME)",) \
			$(if $(EMPLOYEE_SURNAME),--employee-surname "$(EMPLOYEE_SURNAME)",) \
			$(if $(EMPLOYEE_ROLE),--employee-role "$(EMPLOYEE_ROLE)",) \
			$(if $(UPDATED_EMPLOYEE_NAME),--updated-employee-name "$(UPDATED_EMPLOYEE_NAME)",) \
			$(if $(UPDATED_EMPLOYEE_SURNAME),--updated-employee-surname "$(UPDATED_EMPLOYEE_SURNAME)",) \
			$(if $(UPDATED_EMPLOYEE_ROLE),--updated-employee-role "$(UPDATED_EMPLOYEE_ROLE)",)

run-local:
	@$(MAKE) -C "$(ROOT_DIR)" up MODE=bare
	@$(MAKE) run MODE=bare \
		GRAPHQL_URL="$(DEFAULT_GRAPHQL_URL)" \
		EMPLOYEE_ID="$(EMPLOYEE_ID)" \
		EMPLOYEE_NAME="$(EMPLOYEE_NAME)" \
		EMPLOYEE_SURNAME="$(EMPLOYEE_SURNAME)" \
		EMPLOYEE_ROLE="$(EMPLOYEE_ROLE)" \
		UPDATED_EMPLOYEE_NAME="$(UPDATED_EMPLOYEE_NAME)" \
		UPDATED_EMPLOYEE_SURNAME="$(UPDATED_EMPLOYEE_SURNAME)" \
		UPDATED_EMPLOYEE_ROLE="$(UPDATED_EMPLOYEE_ROLE)"

clean:
	@find "$(MAKEFILE_DIR)" -type d -name "__pycache__" -prune -exec rm -rf {} +
	@find "$(MAKEFILE_DIR)" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete

distclean: clean
	@true

help:
	@printf "%s\n" \
		"Usage:" \
		"  make run MODE=docker|bare [GRAPHQL_URL=... ] [EMPLOYEE_ID=12345]" \
		"           [EMPLOYEE_NAME=...] [EMPLOYEE_SURNAME=...] [EMPLOYEE_ROLE=...]" \
		"           [UPDATED_EMPLOYEE_NAME=...] [UPDATED_EMPLOYEE_SURNAME=...]" \
		"           [UPDATED_EMPLOYEE_ROLE=...]" \
		"  make run-local [EMPLOYEE_ID=12345] [EMPLOYEE_NAME=...] [...]" \
		"  make distclean" \
		"" \
		"'make run' executes 'company.py workflow'." \
		"If generated library artifacts are missing, they are created automatically for the selected MODE." \
		"MODE=docker runs the example client in a container." \
		"MODE=bare runs it via the local GraphQL library virtualenv."
