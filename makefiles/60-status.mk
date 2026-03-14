# Module: makefiles/60-status.mk
# ──────────────────────────────────────────────────────────────────────────────
# Cluster Status
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: nodes status pods

nodes: ## Show cluster nodes
	@kubectl get nodes -o wide

status: ## Show all running pods across namespaces
	@kubectl get pods -A | grep -v Completed

pods: ## Show pods with resource usage
	@kubectl top pods -A 2>/dev/null || kubectl get pods -A
