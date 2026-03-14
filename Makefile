.DEFAULT_GOAL := help
SHELL         := /bin/bash

# Load .env if present — exports all variables to sub-processes
-include .env
export

# Defaults (overridable via .env or environment)
SSH_USER            ?= debian
SSH_PORT            ?= 22
SSH_KEY             ?= $(HOME)/.ssh/id_ed25519
SSH_KEY             := $(subst ~,$(HOME),$(SSH_KEY))
INITIAL_USER        ?= root
MASTER_IP           ?=
WORKER_IP           ?=
KUBECONFIG_CONTEXT  ?= k3s-lab
K3S_VERSION         ?= v1.32.2+k3s1

# Root of this repo — used by run-local-script / run-remote-script in local mode
K3S_LAB     := $(abspath $(dir $(MAKEFILE_LIST)))
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main

# Terminal colors
GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
RED    := \033[0;31m
RESET  := \033[0m

include makefiles/00-lib.mk
include makefiles/10-help.mk
include makefiles/20-vps.mk
include makefiles/30-k3s.mk
include makefiles/40-kubeconfig.mk
include makefiles/50-deploy.mk
include makefiles/60-status.mk
include makefiles/70-ssh.mk

# ── Testing ──────────────────────────────────────────────────────────────────

.PHONY: test

test: ## Run BATS unit tests (offline — no cluster needed)
	@bats tests/bats/

# ── Hooks ────────────────────────────────────────────────────────────────────

.PHONY: hooks-update

hooks-update: ## Update prek hook revisions to latest (prek autoupdate)
	@prek autoupdate
