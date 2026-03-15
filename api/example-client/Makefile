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
EMPLOYEE_DESCRIPTION ?=
UPDATED_EMPLOYEE_NAME ?=
UPDATED_EMPLOYEE_SURNAME ?=
UPDATED_EMPLOYEE_DESCRIPTION ?=

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
		EMPLOYEE_DESCRIPTION="$(EMPLOYEE_DESCRIPTION)" \
		UPDATED_EMPLOYEE_NAME="$(UPDATED_EMPLOYEE_NAME)" \
		UPDATED_EMPLOYEE_SURNAME="$(UPDATED_EMPLOYEE_SURNAME)" \
		UPDATED_EMPLOYEE_DESCRIPTION="$(UPDATED_EMPLOYEE_DESCRIPTION)"

bare-run:
	@if [[ ! -x "$(GRAPHQL_LIBRARY_VENV_PYTHON)" ]]; then \
		if [[ -d "$(GRAPHQL_LIBRARY_GENERATED_DIR)/fastapi_graphql_client" ]]; then \
			echo "GraphQL library environment not found for bare mode. The client appears to have been generated in docker mode; run 'make library-generate MODE=bare' first." >&2; \
		else \
			echo "GraphQL library environment not found. Run 'make library-generate MODE=bare' first." >&2; \
		fi; \
		exit 1; \
	fi
	@if [[ ! -d "$(GRAPHQL_LIBRARY_GENERATED_DIR)/fastapi_graphql_client" ]]; then \
		echo "Generated GraphQL library not found. Run 'make library-generate MODE=bare' first." >&2; \
		exit 1; \
	fi
	@cd "$(MAKEFILE_DIR)" && \
		PYTHONPATH="$(GRAPHQL_LIBRARY_GENERATED_DIR)${PYTHONPATH:+:$$PYTHONPATH}" \
		"$(GRAPHQL_LIBRARY_VENV_PYTHON)" employee_workflow.py \
			--graphql-url "$(GRAPHQL_URL)" \
			$(if $(EMPLOYEE_ID),--employee-id "$(EMPLOYEE_ID)",) \
			$(if $(EMPLOYEE_NAME),--employee-name "$(EMPLOYEE_NAME)",) \
			$(if $(EMPLOYEE_SURNAME),--employee-surname "$(EMPLOYEE_SURNAME)",) \
			$(if $(EMPLOYEE_DESCRIPTION),--employee-description "$(EMPLOYEE_DESCRIPTION)",) \
			$(if $(UPDATED_EMPLOYEE_NAME),--updated-employee-name "$(UPDATED_EMPLOYEE_NAME)",) \
			$(if $(UPDATED_EMPLOYEE_SURNAME),--updated-employee-surname "$(UPDATED_EMPLOYEE_SURNAME)",) \
			$(if $(UPDATED_EMPLOYEE_DESCRIPTION),--updated-employee-description "$(UPDATED_EMPLOYEE_DESCRIPTION)",)

docker-run:
	@if [[ ! -d "$(GRAPHQL_LIBRARY_GENERATED_DIR)/fastapi_graphql_client" ]]; then \
		echo "Generated GraphQL library not found. Run 'make library-generate MODE=docker' first." >&2; \
		exit 1; \
	fi
	@$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" docker-deps MODE="docker" API_PORT="$(API_PORT)"
	@$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$(ROOT_DIR):$(DOCKER_API_DIR)" \
		-w "$(DOCKER_WORKDIR)" \
		"$(DOCKER_IMAGE)" \
		env FORCE_COLOR=1 PYTHONPATH="$(DOCKER_API_DIR)/graphql-library/generated" \
		python employee_workflow.py \
			--graphql-url "$(GRAPHQL_URL)" \
			$(if $(EMPLOYEE_ID),--employee-id "$(EMPLOYEE_ID)",) \
			$(if $(EMPLOYEE_NAME),--employee-name "$(EMPLOYEE_NAME)",) \
			$(if $(EMPLOYEE_SURNAME),--employee-surname "$(EMPLOYEE_SURNAME)",) \
			$(if $(EMPLOYEE_DESCRIPTION),--employee-description "$(EMPLOYEE_DESCRIPTION)",) \
			$(if $(UPDATED_EMPLOYEE_NAME),--updated-employee-name "$(UPDATED_EMPLOYEE_NAME)",) \
			$(if $(UPDATED_EMPLOYEE_SURNAME),--updated-employee-surname "$(UPDATED_EMPLOYEE_SURNAME)",) \
			$(if $(UPDATED_EMPLOYEE_DESCRIPTION),--updated-employee-description "$(UPDATED_EMPLOYEE_DESCRIPTION)",)

run-local:
	@$(MAKE) -C "$(ROOT_DIR)" up MODE=bare
	@$(MAKE) run MODE=bare \
		GRAPHQL_URL="$(DEFAULT_GRAPHQL_URL)" \
		EMPLOYEE_ID="$(EMPLOYEE_ID)" \
		EMPLOYEE_NAME="$(EMPLOYEE_NAME)" \
		EMPLOYEE_SURNAME="$(EMPLOYEE_SURNAME)" \
		EMPLOYEE_DESCRIPTION="$(EMPLOYEE_DESCRIPTION)" \
		UPDATED_EMPLOYEE_NAME="$(UPDATED_EMPLOYEE_NAME)" \
		UPDATED_EMPLOYEE_SURNAME="$(UPDATED_EMPLOYEE_SURNAME)" \
		UPDATED_EMPLOYEE_DESCRIPTION="$(UPDATED_EMPLOYEE_DESCRIPTION)"

clean:
	@find "$(MAKEFILE_DIR)" -type d -name "__pycache__" -prune -exec rm -rf {} +
	@find "$(MAKEFILE_DIR)" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete

distclean: clean
	@true

help:
	@printf "%s\n" \
		"Usage:" \
		"  make run MODE=docker|bare [GRAPHQL_URL=... ] [EMPLOYEE_ID=12345]" \
		"           [EMPLOYEE_NAME=...] [EMPLOYEE_SURNAME=...] [EMPLOYEE_DESCRIPTION=...]" \
		"           [UPDATED_EMPLOYEE_NAME=...] [UPDATED_EMPLOYEE_SURNAME=...]" \
		"           [UPDATED_EMPLOYEE_DESCRIPTION=...]" \
		"  make run-local [EMPLOYEE_ID=12345] [EMPLOYEE_NAME=...] [...]" \
		"  make distclean" \
		"" \
		"MODE=docker runs the example client in a container." \
		"MODE=bare runs it via the local GraphQL library virtualenv."
