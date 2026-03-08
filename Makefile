SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
-include $(MAKEFILE_DIR)/ports.env

MODE ?= docker

SERVICES := vault gitea gitlab nexus api jenkins nginx
START_ORDER := $(SERVICES)
STOP_ORDER := nginx jenkins api nexus gitlab gitea vault

.PHONY: help all up down start stop restart status \
	$(SERVICES:%=up-%) \
	$(SERVICES:%=down-%) \
	$(SERVICES:%=status-%) \
	$(SERVICES:%=logs-%)

help:
	@echo "Top-level service orchestration"
	@echo ""
	@echo "Usage:"
	@echo "  make all MODE=docker|bare      # start all services in dependency order"
	@echo "  make up MODE=docker|bare       # same as all"
	@echo "  make down MODE=docker|bare     # stop all services in reverse order"
	@echo "  make start MODE=docker|bare    # alias for up"
	@echo "  make stop MODE=docker|bare     # alias for down"
	@echo "  make status                    # show status for all services"
	@echo ""
	@echo "Per-service:"
	@echo "  make up-vault MODE=docker|bare"
	@echo "  make down-vault MODE=docker|bare"
	@echo "  make status-vault MODE=docker|bare"
	@echo "  make logs-vault MODE=docker|bare"
	@echo "  # Same pattern for: gitea, gitlab, nexus, api, jenkins, nginx"
	@echo ""
	@echo "Service start order: $(START_ORDER)"
	@echo "Service stop order:  $(STOP_ORDER)"

all: up

start: up

stop: down

restart: down up

up:
	@set -euo pipefail; \
	for svc in $(START_ORDER); do \
		echo "==> starting $$svc (MODE=$(MODE))"; \
		$(MAKE) -C "$$svc" up MODE="$(MODE)"; \
	done

down:
	@set -euo pipefail; \
	for svc in $(STOP_ORDER); do \
		echo "==> stopping $$svc (MODE=$(MODE))"; \
		$(MAKE) -C "$$svc" down MODE="$(MODE)"; \
	done

status:
	@set -euo pipefail; \
	for svc in $(START_ORDER); do \
		echo "==> status $$svc (MODE=$(MODE))"; \
		$(MAKE) -C "$$svc" status MODE="$(MODE)"; \
	done

define SERVICE_TARGETS
up-$(1):
	@$(MAKE) -C "$(1)" up MODE="$(MODE)"

down-$(1):
	@$(MAKE) -C "$(1)" down MODE="$(MODE)"

status-$(1):
	@$(MAKE) -C "$(1)" status MODE="$(MODE)"

logs-$(1):
	@$(MAKE) -C "$(1)" logs MODE="$(MODE)"
endef

$(foreach svc,$(SERVICES),$(eval $(call SERVICE_TARGETS,$(svc))))
