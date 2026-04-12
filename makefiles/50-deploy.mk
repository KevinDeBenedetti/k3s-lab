# Module: makefiles/50-deploy.mk
# ──────────────────────────────────────────────────────────────────────────────
# Stack Deployment
# Uses run-local-script from 00-lib.mk (local bash or remote curl, transparent).
# ──────────────────────────────────────────────────────────────────────────────

DASHBOARD_USER ?= admin
GRAFANA_USER   ?= admin

.PHONY: deploy deploy-dashboard-secret deploy-monitoring deploy-grafana-secret

deploy: ## Deploy base stack (Traefik, cert-manager, ClusterIssuers)
	@echo "$(YELLOW)→ Deploying base stack on $(shell kubectl config current-context 2>/dev/null)...$(RESET)"
	@$(call run-local-script,scripts/deploy-stack.sh)
	@echo "$(GREEN)✅ Stack deployed$(RESET)"

deploy-dashboard-secret: ## Create Traefik dashboard BasicAuth secret (requires DASHBOARD_PASSWORD)
	@[ -n "$(DASHBOARD_PASSWORD)" ] || (echo "$(RED)❌ DASHBOARD_PASSWORD is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Creating dashboard auth secret...$(RESET)"
	@$(K) create secret generic traefik-dashboard-auth \
		--from-literal=users="$$(htpasswd -nb $(DASHBOARD_USER) $(DASHBOARD_PASSWORD))" \
		-n ingress \
		--dry-run=client -o yaml | $(K) apply -f -
	@echo "$(GREEN)✅ Dashboard secret created$(RESET)"

deploy-monitoring: ## Deploy observability stack (Prometheus + Grafana + Loki + Promtail)
	@[ -n "$(GRAFANA_DOMAIN)" ] || (echo "$(RED)❌ GRAFANA_DOMAIN not set — add to .env$(RESET)"; exit 1)
	@[ -n "$(GRAFANA_PASSWORD)" ] || (echo "$(RED)❌ GRAFANA_PASSWORD not set — run make deploy-grafana-secret first$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Deploying observability stack...$(RESET)"
	@$(call run-local-script,scripts/deploy-monitoring.sh)
	@echo "$(YELLOW)→ Syncing Grafana admin password (grafana-cli reset)...$(RESET)"
	@$(K) exec -n monitoring deployment/kube-prometheus-stack-grafana \
		-- grafana-cli admin reset-admin-password "$(GRAFANA_PASSWORD)"
	@echo "$(GREEN)✅ Observability stack deployed$(RESET)"

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
