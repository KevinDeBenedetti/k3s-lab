# Module: makefiles/50-deploy.mk
# ──────────────────────────────────────────────────────────────────────────────
# Stack Deployment
#
# Base stack and monitoring are now deployed via Helm umbrella charts + ArgoCD.
# These targets are kept for backward compatibility but point to chart-based
# deployments. Secret creation targets remain unchanged.
# ──────────────────────────────────────────────────────────────────────────────

DASHBOARD_USER ?= admin
GRAFANA_USER   ?= admin

.PHONY: deploy deploy-dashboard-secret deploy-monitoring deploy-grafana-secret

deploy: ## ⚠️ DEPRECATED — base stack is now deployed via charts + ArgoCD
	@echo "$(RED)❌ 'make deploy' is deprecated.$(RESET)"
	@echo ""
	@echo "  The base stack is now deployed via Helm umbrella charts + ArgoCD."
	@echo "  Bootstrap sequence:"
	@echo "    1. helm upgrade --install platform-base ./charts/platform-base -n kube-system"
	@echo "    2. make deploy-argocd"
	@echo "    3. Apply ArgoCD ApplicationSets from your infra repo"
	@echo ""
	@exit 1

deploy-dashboard-secret: ## Create Traefik dashboard BasicAuth secret (requires DASHBOARD_PASSWORD)
	@[ -n "$(DASHBOARD_PASSWORD)" ] || (echo "$(RED)❌ DASHBOARD_PASSWORD is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Creating dashboard auth secret...$(RESET)"
	@$(K) create secret generic traefik-dashboard-auth \
		--from-literal=users="$$(htpasswd -nb $(DASHBOARD_USER) $(DASHBOARD_PASSWORD))" \
		-n ingress \
		--dry-run=client -o yaml | $(K) apply -f -
	@echo "$(GREEN)✅ Dashboard secret created$(RESET)"

deploy-monitoring: ## ⚠️ DEPRECATED — monitoring is now deployed via charts/platform-monitoring + ArgoCD
	@echo "$(RED)❌ 'make deploy-monitoring' is deprecated.$(RESET)"
	@echo ""
	@echo "  The observability stack is now deployed via the platform-monitoring chart + ArgoCD."
	@echo "  See: charts/platform-monitoring/"
	@echo ""
	@exit 1

deploy-grafana-secret: ## Create Grafana admin secret (requires GRAFANA_PASSWORD)
	@[ -n "$(GRAFANA_PASSWORD)" ] || (echo "$(RED)❌ GRAFANA_PASSWORD is not set$(RESET)"; exit 1)
	@$(K) cluster-info --request-timeout=5s >/dev/null 2>&1 || \
		(echo "$(RED)❌ Cannot reach cluster $(KUBECONFIG_CONTEXT) — is k3s running? Try: ssh kevin@<VPS> 'sudo systemctl restart k3s'$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Creating monitoring namespace + Grafana admin secret...$(RESET)"
	@$(K) create namespace monitoring --dry-run=client -o yaml \
		| $(K) apply -f -
	@$(K) create secret generic grafana-admin-secret \
		--from-literal=username=$(GRAFANA_USER) \
		--from-literal=password="$(GRAFANA_PASSWORD)" \
		-n monitoring \
		--dry-run=client -o yaml | $(K) apply -f -
	@echo "$(GREEN)✅ Grafana admin secret created$(RESET)"
