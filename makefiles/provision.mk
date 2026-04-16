# Module: makefiles/provision.mk
# ──────────────────────────────────────────────────────────────────────────────
# Ansible-based provisioning workflow
# ──────────────────────────────────────────────────────────────────────────────

# Ansible paths — overridden by consumer repos (e.g. infra/Makefile)
ANSIBLE_DIR     ?= ansible
ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_INVENTORY ?= $(ANSIBLE_DIR)/inventory/hosts.yml
PLAYBOOK_DIR    ?= $(ANSIBLE_DIR)/playbooks
TF_DIR          ?= terraform
CLUSTER_ENV     ?=

.PHONY: inventory provision provision-server provision-agents provision-reset

inventory: ## Generate Ansible inventory from Terraform outputs (requires CLUSTER_ENV)
	$(call require-var,CLUSTER_ENV)
	@echo "$(YELLOW)→ Generating Ansible inventory...$(RESET)"
	@CLUSTER_ENV="$(CLUSTER_ENV)" \
	 TF_DIR="$(TF_DIR)" \
	 ANSIBLE_DIR="$(ANSIBLE_DIR)" \
	 $(call run-local-script,scripts/generate-inventory.sh)

provision: ## Full Ansible provisioning: common + k3s server + agents + kubeconfig
	@[ -f "$(ANSIBLE_INVENTORY)" ] || (echo "$(RED)❌ $(ANSIBLE_INVENTORY) not found — run 'make inventory' first$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Running full Ansible provisioning...$(RESET)"
	@$(ANSIBLE_PLAYBOOK) -i "$(ANSIBLE_INVENTORY)" "$(PLAYBOOK_DIR)/site.yml"
	@echo ""
	@echo "$(GREEN)🎉 Cluster provisioned!$(RESET)"
	@echo "  kubectl config use-context $(KUBECONFIG_CONTEXT)"
	@echo "  make nodes"
	@echo ""
	@echo "$(YELLOW)Next steps:$(RESET)"
	@echo "  make deploy                  # Deploy base stack (Traefik + cert-manager)"
	@echo "  make deploy-monitoring       # Deploy observability stack"
	@echo "  make status                  # Check all pods"

provision-server: ## Provision server node only (common + k3s server + wireguard)
	@[ -f "$(ANSIBLE_INVENTORY)" ] || (echo "$(RED)❌ $(ANSIBLE_INVENTORY) not found — run 'make inventory' first$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Provisioning server node...$(RESET)"
	@$(ANSIBLE_PLAYBOOK) -i "$(ANSIBLE_INVENTORY)" "$(PLAYBOOK_DIR)/k3s-server.yml"

provision-agents: ## Add agent nodes to existing cluster
	@[ -f "$(ANSIBLE_INVENTORY)" ] || (echo "$(RED)❌ $(ANSIBLE_INVENTORY) not found — run 'make inventory' first$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Provisioning agent nodes...$(RESET)"
	@$(ANSIBLE_PLAYBOOK) -i "$(ANSIBLE_INVENTORY)" "$(PLAYBOOK_DIR)/k3s-agent.yml"

provision-reset: ## Uninstall k3s from all nodes (DESTRUCTIVE)
	@[ -f "$(ANSIBLE_INVENTORY)" ] || (echo "$(RED)❌ $(ANSIBLE_INVENTORY) not found$(RESET)"; exit 1)
	@echo "$(RED)→ Resetting k3s on all nodes...$(RESET)"
	@$(ANSIBLE_PLAYBOOK) -i "$(ANSIBLE_INVENTORY)" "$(PLAYBOOK_DIR)/reset.yml"
