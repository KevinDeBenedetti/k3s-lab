# Module: makefiles/50-deploy.mk
# ──────────────────────────────────────────────────────────────────────────────
# Stack Deployment — Secret creation targets
#
# Base stack and monitoring are deployed via Helm umbrella charts + ArgoCD.
# ──────────────────────────────────────────────────────────────────────────────

DASHBOARD_USER ?= admin
GRAFANA_USER   ?= admin

.PHONY: deploy-dashboard-secret deploy-grafana-secret deploy-grafana-oauth uninstall

deploy-dashboard-secret: ## Create Traefik dashboard BasicAuth secret (requires DASHBOARD_PASSWORD)
	$(call require-var,DASHBOARD_PASSWORD)
	@echo "$(YELLOW)→ Creating dashboard auth secret...$(RESET)"
	@$(call create-k8s-secret,traefik-dashboard-auth,ingress,--from-literal=users="$$(htpasswd -nb $(DASHBOARD_USER) $(DASHBOARD_PASSWORD))")
	@echo "$(GREEN)✅ Dashboard secret created$(RESET)"

deploy-grafana-secret: ## Create Grafana admin secret (requires GRAFANA_PASSWORD)
	$(call require-var,GRAFANA_PASSWORD)
	@$(K) cluster-info --request-timeout=5s >/dev/null 2>&1 || \
		(echo "$(RED)❌ Cannot reach cluster $(KUBECONFIG_CONTEXT) — is k3s running? Try: ssh kevin@<VPS> 'sudo systemctl restart k3s'$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Creating monitoring namespace + Grafana admin secret...$(RESET)"
	@$(K) create namespace monitoring --dry-run=client -o yaml \
		| $(K) apply -f -
	@$(call create-k8s-secret,grafana-admin-secret,monitoring,--from-literal=username=$(GRAFANA_USER) --from-literal=password="$(GRAFANA_PASSWORD)")
	@echo "$(GREEN)✅ Grafana admin secret created$(RESET)"

deploy-grafana-oauth: ## Restart Grafana to pick up OAuth secret from Vault
	$(call require-var,GRAFANA_DOMAIN)
	@GRAFANA_DOMAIN="$(GRAFANA_DOMAIN)" \
	 $(call run-local-script,scripts/deploy-grafana-oauth.sh)

uninstall: ## Tear down all deployed workloads (DESTRUCTIVE)
	@$(call run-local-script,scripts/uninstall.sh)
