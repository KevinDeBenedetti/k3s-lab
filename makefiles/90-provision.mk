# Module: makefiles/90-provision.mk
# ──────────────────────────────────────────────────────────────────────────────
# Full provisioning workflow
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: provision

provision: setup-all k3s-server k3s-agent kubeconfig deploy deploy-dashboard-secret deploy-grafana-secret deploy-monitoring ## Full provision: setup VPS → k3s → kubeconfig → deploy stack → secrets → monitoring
	@echo ""
	@echo "$(GREEN)🎉 Cluster ready!$(RESET)"
	@echo "  kubectl config use-context $(KUBECONFIG_CONTEXT)"
	@echo "  make nodes"
