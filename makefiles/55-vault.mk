# Module: makefiles/55-vault.mk
# ──────────────────────────────────────────────────────────────────────────────
# HashiCorp Vault + External Secrets Operator
# ──────────────────────────────────────────────────────────────────────────────

VAULT_CHART_VERSION ?= 0.29.1
ESO_CHART_VERSION   ?= 0.14.3
VAULT_DOMAIN        ?=
VAULT_ROOT_TOKEN    ?=   # optional: set to skip interactive prompt in vault-init

.PHONY: deploy-vault vault-init vault-unseal vault-configure vault-seed vault-status deploy-eso

deploy-vault: ## Deploy HashiCorp Vault via Helm (sealed — run make vault-init next)
	@[ -n "$(VAULT_DOMAIN)" ] || (echo "$(RED)❌ VAULT_DOMAIN not set — add to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Deploying Vault $(VAULT_CHART_VERSION)...$(RESET)"
	@DEPLOY_VAULT=true DEPLOY_ESO=false \
	  VAULT_CHART_VERSION=$(VAULT_CHART_VERSION) \
	  VAULT_DOMAIN=$(VAULT_DOMAIN) \
	  $(call run-local-script,scripts/deploy-vault.sh)
	@echo ""
	@echo "$(GREEN)✅ Vault deployed$(RESET)"
	@echo "$(YELLOW)Next: make vault-init$(RESET)"

deploy-eso: ## Deploy External Secrets Operator via Helm
	@echo "$(YELLOW)→ Deploying External Secrets Operator $(ESO_CHART_VERSION)...$(RESET)"
	@DEPLOY_VAULT=false DEPLOY_ESO=true \
	  ESO_CHART_VERSION=$(ESO_CHART_VERSION) \
	  $(call run-local-script,scripts/deploy-vault.sh)
	@echo "$(GREEN)✅ External Secrets Operator deployed$(RESET)"

vault-init: ## Initialize Vault, unseal, enable K8s auth, create policies + ESO role
	@echo "$(YELLOW)→ Initializing Vault...$(RESET)"
	@echo "$(YELLOW)⚠️  Save the unseal keys and root token — they will not be shown again$(RESET)"
	@$(call run-local-script,scripts/vault-init.sh)

vault-unseal: ## Unseal Vault after a node reboot (requires VAULT_UNSEAL_KEY_1 + KEY_2 in .env)
	@[ -n "$(VAULT_UNSEAL_KEY_1)" ] || (echo "$(RED)❌ VAULT_UNSEAL_KEY_1 not set$(RESET)"; exit 1)
	@[ -n "$(VAULT_UNSEAL_KEY_2)" ] || (echo "$(RED)❌ VAULT_UNSEAL_KEY_2 not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Unsealing Vault...$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	  vault operator unseal $(VAULT_UNSEAL_KEY_1)
	@kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	  vault operator unseal $(VAULT_UNSEAL_KEY_2)
	@echo "$(GREEN)✅ Vault unsealed$(RESET)"

vault-configure: ## (Re)create Vault policies and Kubernetes roles (idempotent)
	@[ -n "$(VAULT_ROOT_TOKEN)" ] || (echo "$(RED)❌ VAULT_ROOT_TOKEN not set — add to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Configuring Vault policies and roles...$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 \
	  -e VAULT_TOKEN=$(VAULT_ROOT_TOKEN) -- \
	  sh -c ' \
	    vault policy write eso-read - <<EOF\n\
path "secret/data/*" { capabilities = ["read", "list"] }\n\
path "secret/metadata/*" { capabilities = ["read", "list"] }\n\
EOF\n\
	    vault write auth/kubernetes/role/eso \
	      bound_service_account_names=external-secrets \
	      bound_service_account_namespaces=external-secrets \
	      policies=eso-read \
	      ttl=1h \
	  '
	@echo "$(GREEN)✅ Vault configured$(RESET)"

vault-seed: ## Interactively store all managed secrets into Vault
	@[ -n "$(VAULT_ROOT_TOKEN)" ] || (echo "$(RED)❌ VAULT_ROOT_TOKEN not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Seeding secrets into Vault...$(RESET)"
	@echo "$(CYAN)Enter values for each secret (leave blank to skip):$(RESET)"
	@echo ""
	@read -p "  INFOMANIAK_CLIENT_ID    : " _oidc_id;     \
	 read -p "  INFOMANIAK_CLIENT_SECRET: " _oidc_secret; \
	 [ -n "$$_oidc_id" ] && \
	   kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/argocd/oidc \
	       clientID="$$_oidc_id" \
	       clientSecret="$$_oidc_secret" \
	  || echo "  (skipped argocd/oidc)"
	@echo ""
	@read -p "  GRAFANA_PASSWORD        : " _grafana_pw; \
	 [ -n "$$_grafana_pw" ] && \
	   kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/grafana/admin \
	       username="admin" \
	       password="$$_grafana_pw" \
	  || echo "  (skipped grafana/admin)"
	@echo ""
	@read -p "  INFOMANIAK_CLIENT_ID (Grafana — same app? y/n): " _same; \
	 if [ "$$_same" = "y" ]; then \
	   read -p "  GF_AUTH CLIENT_ID    : " _gf_id; \
	   read -p "  GF_AUTH CLIENT_SECRET: " _gf_sec; \
	   [ -n "$$_gf_id" ] && \
	     kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	       env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	       vault kv put secret/grafana/oauth \
	         GF_AUTH_GENERIC_OAUTH_ENABLED="true" \
	         GF_AUTH_GENERIC_OAUTH_NAME="Infomaniak" \
	         GF_AUTH_GENERIC_OAUTH_CLIENT_ID="$$_gf_id" \
	         GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="$$_gf_sec" \
	         GF_AUTH_GENERIC_OAUTH_SCOPES="openid email profile" \
	         GF_AUTH_GENERIC_OAUTH_AUTH_URL="https://login.infomaniak.com/authorize" \
	         GF_AUTH_GENERIC_OAUTH_TOKEN_URL="https://login.infomaniak.com/token" \
	         GF_AUTH_GENERIC_OAUTH_API_URL="https://login.infomaniak.com/userinfo" \
	         GF_AUTH_GENERIC_OAUTH_USE_PKCE="true" \
	         GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN="true" \
	         GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN="true" \
	         GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP="true" \
	         GF_AUTH_DISABLE_LOGIN_FORM="true" \
	  || echo "  (skipped grafana/oauth)"; fi
	@echo ""
	@read -p "  DASHBOARD_PASSWORD      : " _dash_pw; \
	 [ -n "$$_dash_pw" ] && \
	   kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/traefik/dashboard \
	       password="$$_dash_pw" \
	  || echo "  (skipped traefik/dashboard)"
	@echo ""
	@echo "$(GREEN)✅ Vault secrets seeded$(RESET)"

vault-status: ## Show Vault seal status, ESO sync status, and managed secrets
	@echo ""
	@echo "$(CYAN)── Vault ────────────────────────────────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) exec -n vault vault-0 -- \
	  vault status 2>/dev/null || echo "$(RED)❌ Vault pod not reachable$(RESET)"
	@echo ""
	@echo "$(CYAN)── External Secrets (sync status) ──────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) get externalsecrets -A \
	  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,REFRESH:.status.refreshTime' \
	  2>/dev/null || echo "$(RED)❌ ESO not installed or no ExternalSecrets found$(RESET)"
	@echo ""
	@echo "$(CYAN)── ClusterSecretStore ───────────────────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) get clustersecretstore \
	  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[0].status' \
	  2>/dev/null || echo "  (none)"
	@echo ""
