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
SERVER_IP           ?=
AGENT_IP            ?=
KUBECONFIG_CONTEXT  ?= k3s-lab
K3S_VERSION         ?= v1.32.2+k3s1

# Root of this repo — used by run-local-script / run-remote-script in local mode
K3S_LAB     := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main

# Terminal colors
GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
RED    := \033[0;31m
RESET  := \033[0m

include makefiles/00-lib.mk
include makefiles/10-help.mk
include makefiles/40-kubeconfig.mk
include makefiles/45-security.mk
include makefiles/50-deploy.mk
include makefiles/51-external-dns.mk
include makefiles/52-argocd.mk
include makefiles/55-vault.mk
include makefiles/60-status.mk
include makefiles/70-ssh.mk
include makefiles/80-dev.mk
include makefiles/90-provision.mk
