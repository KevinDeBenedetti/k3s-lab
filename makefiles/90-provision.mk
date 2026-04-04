# Module: makefiles/90-provision.mk
# ──────────────────────────────────────────────────────────────────────────────
# Full provisioning workflow
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: provision

provision: setup-all k3s-server k3s-agent kubeconfig deploy deploy-dashboard-secret deploy-grafana-secret deploy-monitoring deploy-vault vault-init deploy-eso deploy-argocd ## Full provision: VPS → k3s → kubeconfig → stack → secrets → monitoring → vault → argocd
	@echo ""
	@echo "$(GREEN)🎉 Cluster ready!$(RESET)"
	@echo "  kubectl config use-context $(KUBECONFIG_CONTEXT)"
	@echo "  make nodes"
	@echo ""
	@echo "$(YELLOW)Post-provision steps:$(RESET)"
	@echo "  make vault-seed              # Store OIDC + Grafana secrets in Vault"
	@echo "  make deploy-eso              # Deploy External Secrets Operator (if not done)"
	@echo "  make argocd-add-repo         # Register your infra Git repo in ArgoCD"
	@echo "  make argocd-deploy-apps      # Deploy ArgoCD Applications"
	@echo "  make health                  # Full cluster health check"
