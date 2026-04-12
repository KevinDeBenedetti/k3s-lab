# Module: makefiles/60-status.mk
# ──────────────────────────────────────────────────────────────────────────────
# Cluster Status
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: nodes status pods cert-status

nodes: ## Show cluster nodes
	@$(K) get nodes -o wide

status: ## Show all running pods across namespaces
	@$(K) get pods -A | grep -v Completed

pods: ## Show pods with resource usage
	@$(K) top pods -A 2>/dev/null \
	  || $(K) get pods -A

cert-status: ## Show cert-manager certificate status across all namespaces
	@echo "$(CYAN)── Certificates ────────────────────────────────────────────────$(RESET)"
	@$(K) get certificates -A \
	  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter' \
	  2>/dev/null || echo "$(RED)❌ cert-manager not reachable$(RESET)"
