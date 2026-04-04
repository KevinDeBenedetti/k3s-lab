# Module: makefiles/60-status.mk
# ──────────────────────────────────────────────────────────────────────────────
# Cluster Status
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: nodes status pods cert-status

nodes: ## Show cluster nodes
	@kubectl --context $(KUBECONFIG_CONTEXT) get nodes -o wide

status: ## Show all running pods across namespaces
	@kubectl --context $(KUBECONFIG_CONTEXT) get pods -A | grep -v Completed

pods: ## Show pods with resource usage
	@kubectl --context $(KUBECONFIG_CONTEXT) top pods -A 2>/dev/null \
	  || kubectl --context $(KUBECONFIG_CONTEXT) get pods -A

cert-status: ## Show cert-manager certificate status across all namespaces
	@echo "$(CYAN)── Certificates ────────────────────────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) get certificates -A \
	  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter' \
	  2>/dev/null || echo "$(RED)❌ cert-manager not reachable$(RESET)"
