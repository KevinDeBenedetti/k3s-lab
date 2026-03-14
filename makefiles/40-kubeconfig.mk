# Module: makefiles/40-kubeconfig.mk
# ──────────────────────────────────────────────────────────────────────────────
# Kubeconfig
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: kubeconfig

kubeconfig: ## Fetch kubeconfig from master and merge into ~/.kube/config
	@[ -n "$(MASTER_IP)" ] || (echo "$(RED)❌ MASTER_IP is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Fetching kubeconfig from $(MASTER_IP)...$(RESET)"
	@SSH_KEY=$(SSH_KEY) SSH_PORT=$(SSH_PORT) bash $(K3S_HOMELAB)/scripts/get-kubeconfig.sh $(MASTER_IP) $(SSH_USER) $(KUBECONFIG_CONTEXT)
	@echo "$(GREEN)✅ Context '$(KUBECONFIG_CONTEXT)' ready$(RESET)"
	@echo "  kubectl config use-context $(KUBECONFIG_CONTEXT)"
