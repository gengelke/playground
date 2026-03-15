SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
FASTAPI_DIR := $(MAKEFILE_DIR)fastapi
GRAPHQL_LIBRARY_DIR := $(MAKEFILE_DIR)graphql-library
EXAMPLE_CLIENT_DIR := $(MAKEFILE_DIR)example-client
MODE ?= docker
LIBRARY_SCHEMA_SOURCE ?= $(if $(filter docker,$(MODE)),remote,local)
LIBRARY_REMOTE_SCHEMA_URL ?= $(if $(filter docker,$(MODE)),http://host.docker.internal:8000/graphql,http://127.0.0.1:8000/graphql)
RUN_GRAPHQL_URL ?= http://127.0.0.1:8000/graphql
RUN_GRAPHQL_URL_DOCKER ?= $(subst http://localhost,http://host.docker.internal,$(subst http://127.0.0.1,http://host.docker.internal,$(RUN_GRAPHQL_URL)))
EMPLOYEE_ID ?=
EMPLOYEE_NAME ?=
EMPLOYEE_SURNAME ?=
EMPLOYEE_ROLE ?=
UPDATED_EMPLOYEE_NAME ?=
UPDATED_EMPLOYEE_SURNAME ?=
UPDATED_EMPLOYEE_ROLE ?=
SANITIZE_TLS_ENV = \
	for cert_var in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE PIP_CERT; do \
		cert_path="$${!cert_var:-}"; \
		if [[ -n "$$cert_path" && ! -f "$$cert_path" ]]; then \
			echo "Ignoring invalid $$cert_var=$$cert_path" >&2; \
			unset "$$cert_var"; \
		fi; \
	done;

.PHONY: help build up down restart logs status run clean distclean \
	fastapi-run \
	library-help library-deps library-generate library-clean library-distclean

help:
	@printf "%s\n" \
		"FastAPI service:" \
		"  make build MODE=docker|bare" \
		"  make up MODE=docker|bare" \
		"  make down MODE=docker|bare" \
		"  make logs MODE=docker|bare" \
		"  make status MODE=docker|bare" \
		"  make fastapi-run" \
		"" \
		"GraphQL client library:" \
		"  make library-generate MODE=docker|bare [LIBRARY_SCHEMA_SOURCE=local|remote]" \
		"  make library-deps MODE=docker|bare" \
		"  make library-clean MODE=docker|bare" \
		"  make library-distclean MODE=docker|bare" \
		"" \
		"End-to-end example:" \
		"  make run MODE=docker|bare [EMPLOYEE_ID=12345] [EMPLOYEE_NAME=...] [EMPLOYEE_SURNAME=...]" \
		"           [EMPLOYEE_ROLE=...] [UPDATED_EMPLOYEE_NAME=...]" \
		"           [UPDATED_EMPLOYEE_SURNAME=...] [UPDATED_EMPLOYEE_ROLE=...]" \
		"" \
		"Library variables:" \
		"  MODE=$(MODE)" \
		"  LIBRARY_SCHEMA_SOURCE=$(LIBRARY_SCHEMA_SOURCE)" \
		"  LIBRARY_REMOTE_SCHEMA_URL=$(LIBRARY_REMOTE_SCHEMA_URL)" \
		"" \
		"Run variables:" \
		"  RUN_GRAPHQL_URL=$(RUN_GRAPHQL_URL)" \
		"  RUN_GRAPHQL_URL_DOCKER=$(RUN_GRAPHQL_URL_DOCKER)" \
		"  EMPLOYEE_ID=$(EMPLOYEE_ID)" \
		"  EMPLOYEE_NAME=$(EMPLOYEE_NAME)" \
		"  EMPLOYEE_SURNAME=$(EMPLOYEE_SURNAME)" \
		"  EMPLOYEE_ROLE=$(EMPLOYEE_ROLE)" \
		"  UPDATED_EMPLOYEE_NAME=$(UPDATED_EMPLOYEE_NAME)" \
		"  UPDATED_EMPLOYEE_SURNAME=$(UPDATED_EMPLOYEE_SURNAME)" \
		"  UPDATED_EMPLOYEE_ROLE=$(UPDATED_EMPLOYEE_ROLE)"

build up down restart logs status clean:
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(FASTAPI_DIR)" $@ MODE="$(MODE)"

fastapi-run:
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(FASTAPI_DIR)" run MODE="bare"

run:
	@$(SANITIZE_TLS_ENV) \
	if [[ "$(MODE)" == "bare" ]]; then \
		needs_library=0; \
		if [[ ! -x "$(GRAPHQL_LIBRARY_DIR)/.venv/bin/python" ]]; then \
			needs_library=1; \
		fi; \
		if [[ ! -d "$(GRAPHQL_LIBRARY_DIR)/generated/fastapi_graphql_client" ]]; then \
			needs_library=1; \
		fi; \
		if [[ "$$needs_library" == "1" ]]; then \
			$(MAKE) library-generate MODE=bare; \
		fi; \
	elif [[ ! -d "$(GRAPHQL_LIBRARY_DIR)/generated/fastapi_graphql_client" ]]; then \
		$(MAKE) library-generate MODE="$(MODE)"; \
	fi
	@$(SANITIZE_TLS_ENV) \
	if [[ "$(MODE)" == "docker" ]]; then \
		$(MAKE) -C "$(FASTAPI_DIR)" down MODE=bare >/dev/null 2>&1 || true; \
	else \
		$(MAKE) -C "$(FASTAPI_DIR)" down MODE=docker >/dev/null 2>&1 || true; \
	fi
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) up MODE="$(MODE)"
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(EXAMPLE_CLIENT_DIR)" run \
			MODE="$(MODE)" \
			GRAPHQL_URL="$(if $(filter docker,$(MODE)),$(RUN_GRAPHQL_URL_DOCKER),$(RUN_GRAPHQL_URL))" \
			EMPLOYEE_ID="$(EMPLOYEE_ID)" \
			EMPLOYEE_NAME="$(EMPLOYEE_NAME)" \
			EMPLOYEE_SURNAME="$(EMPLOYEE_SURNAME)" \
			EMPLOYEE_ROLE="$(EMPLOYEE_ROLE)" \
			UPDATED_EMPLOYEE_NAME="$(UPDATED_EMPLOYEE_NAME)" \
			UPDATED_EMPLOYEE_SURNAME="$(UPDATED_EMPLOYEE_SURNAME)" \
			UPDATED_EMPLOYEE_ROLE="$(UPDATED_EMPLOYEE_ROLE)"

distclean:
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(FASTAPI_DIR)" distclean MODE="$(MODE)"
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" distclean \
			MODE="$(MODE)" \
			SCHEMA_SOURCE="$(LIBRARY_SCHEMA_SOURCE)" \
			REMOTE_SCHEMA_URL="$(LIBRARY_REMOTE_SCHEMA_URL)"
	@$(MAKE) -C "$(EXAMPLE_CLIENT_DIR)" distclean

library-help:
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" help \
			MODE="$(MODE)" \
			SCHEMA_SOURCE="$(LIBRARY_SCHEMA_SOURCE)" \
			REMOTE_SCHEMA_URL="$(LIBRARY_REMOTE_SCHEMA_URL)"

library-deps library-generate library-clean library-distclean:
	@$(SANITIZE_TLS_ENV) \
		$(MAKE) -C "$(GRAPHQL_LIBRARY_DIR)" $(patsubst library-%,%,$@) \
			MODE="$(MODE)" \
			SCHEMA_SOURCE="$(LIBRARY_SCHEMA_SOURCE)" \
			REMOTE_SCHEMA_URL="$(LIBRARY_REMOTE_SCHEMA_URL)"
