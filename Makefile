SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
-include $(MAKEFILE_DIR)/ports.env

MODE ?= docker

SERVICES := vault gitea gitlab nexus api jenkins nginx ollama chatbot
START_ORDER := $(SERVICES)
STOP_ORDER := chatbot ollama nginx jenkins api nexus gitlab gitea vault
DEVOPS_ORDER := vault nexus api gitea jenkins nginx ollama chatbot
DEVOPS_STOP_ORDER := chatbot ollama nginx jenkins gitea api nexus vault
DISTCLEAN_ORDER := chatbot ollama nginx jenkins api nexus gitlab gitea vault

.PHONY: help all up down start stop restart status \
	devops devops-up devops-down devops-stop \
	distclean distclan \
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
	@echo "  make devops MODE=docker|bare   # start vault,nexus,api,gitea,jenkins,nginx,ollama,chatbot"
	@echo "  make devops-down MODE=docker|bare # stop chatbot,ollama,nginx,jenkins,gitea,api,nexus,vault"
	@echo "  make distclean                 # remove generated deployment artifacts"
	@echo "  make distclan                  # alias for distclean"
	@echo "  make status                    # show status for all services"
	@echo ""
	@echo "Per-service:"
	@for svc in $(SERVICES); do \
		echo "  $$svc:"; \
		echo "    make up-$$svc MODE=docker|bare"; \
		echo "    make down-$$svc MODE=docker|bare"; \
		echo "    make status-$$svc MODE=docker|bare"; \
		echo "    make logs-$$svc MODE=docker|bare"; \
		echo ""; \
	done
	@echo "Service start order: $(START_ORDER)"
	@echo "Service stop order:  $(STOP_ORDER)"
	@echo "Devops start order:  $(DEVOPS_ORDER)"
	@echo "Devops stop order:   $(DEVOPS_STOP_ORDER)"

all: up

start: up

stop: down

restart: down up

devops: devops-up

devops-stop: devops-down

devops-up:
	@set -euo pipefail; \
	for svc in $(DEVOPS_ORDER); do \
		echo "==> starting $$svc (MODE=$(MODE))"; \
		$(MAKE) -C "$$svc" up MODE="$(MODE)"; \
	done

devops-down:
	@set -euo pipefail; \
	for svc in $(DEVOPS_STOP_ORDER); do \
		echo "==> stopping $$svc (MODE=$(MODE))"; \
		$(MAKE) -C "$$svc" down MODE="$(MODE)"; \
	done

distclean:
	@set -euo pipefail; \
	for svc in $(DISTCLEAN_ORDER); do \
		echo "==> distclean $$svc"; \
		$(MAKE) -C "$$svc" distclean; \
	done

distclan: distclean

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
