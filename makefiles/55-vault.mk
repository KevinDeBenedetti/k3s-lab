# Module: makefiles/55-vault.mk
# ──────────────────────────────────────────────────────────────────────────────
# HashiCorp Vault + External Secrets Operator
# ──────────────────────────────────────────────────────────────────────────────

VAULT_CHART_VERSION ?= 0.29.1
ESO_CHART_VERSION   ?= 0.14.3
VAULT_POD           ?= vault-0
VAULT_NAMESPACE     ?= vault
DASHBOARD_USER      ?= admin
# VAULT_DOMAIN and VAULT_ROOT_TOKEN intentionally have no default here.
# Set them in the consuming Makefile or .env.

# ── Generic OIDC variables (used by vault-seed) ───────────────────────────────
# Consuming repos map their provider-specific vars to these:
#   OIDC_CLIENT_ID     ?= $(MYPROVIDER_CLIENT_ID)
#   OIDC_CLIENT_SECRET ?= $(MYPROVIDER_CLIENT_SECRET)
#   OIDC_PROVIDER_NAME ?= MyProvider
#   OIDC_ISSUER_URL    ?= https://auth.example.com
#   OIDC_AUTH_URL      ?= https://auth.example.com/authorize
#   OIDC_TOKEN_URL     ?= https://auth.example.com/token
#   OIDC_API_URL       ?= https://auth.example.com/userinfo
OIDC_CLIENT_ID     ?=
OIDC_CLIENT_SECRET ?=
OIDC_PROVIDER_NAME ?= OIDC
OIDC_ISSUER_URL    ?=
OIDC_AUTH_URL      ?=
OIDC_TOKEN_URL     ?=
OIDC_API_URL       ?=

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
	@VAULT_POD="$(VAULT_POD)" \
	 VAULT_NAMESPACE="$(VAULT_NAMESPACE)" \
	 OIDC_CLIENT_ID="$(OIDC_CLIENT_ID)" \
	 OIDC_CLIENT_SECRET="$(OIDC_CLIENT_SECRET)" \
	 OIDC_ISSUER_URL="$(OIDC_ISSUER_URL)" \
	 VAULT_DOMAIN="$(VAULT_DOMAIN)" \
	 ADMIN_EMAIL="$(ADMIN_EMAIL)" \
	 $(call run-local-script,scripts/vault-init.sh)

vault-unseal: ## Unseal Vault after a node reboot (requires VAULT_UNSEAL_KEY_1 + KEY_2 in .env)
	@[ -n "$(VAULT_UNSEAL_KEY_1)" ] || (echo "$(RED)❌ VAULT_UNSEAL_KEY_1 not set$(RESET)"; exit 1)
	@[ -n "$(VAULT_UNSEAL_KEY_2)" ] || (echo "$(RED)❌ VAULT_UNSEAL_KEY_2 not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Unsealing Vault...$(RESET)"
	@$(K) exec -n vault $(VAULT_POD) -- \
	  vault operator unseal $(VAULT_UNSEAL_KEY_1)
	@$(K) exec -n vault $(VAULT_POD) -- \
	  vault operator unseal $(VAULT_UNSEAL_KEY_2)
	@echo "$(GREEN)✅ Vault unsealed$(RESET)"

vault-configure: ## (Re)create Vault policies and Kubernetes roles (idempotent)
	@[ -n "$(VAULT_ROOT_TOKEN)" ] || (echo "$(RED)❌ VAULT_ROOT_TOKEN not set — add to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Configuring Vault policies and roles...$(RESET)"
	@printf 'path "secret/data/*" {\n  capabilities = ["read", "list"]\n}\npath "secret/metadata/*" {\n  capabilities = ["read", "list"]\n}\n' \
	  | $(K) exec -i -n vault $(VAULT_POD) -- \
	    env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault policy write eso-read -
	@$(K) exec -n vault $(VAULT_POD) -- \
	  env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault write auth/kubernetes/role/eso \
	    bound_service_account_names=external-secrets \
	    bound_service_account_namespaces=external-secrets \
	    policies=eso-read \
	    ttl=1h
	@if [ -n "$(OIDC_CLIENT_ID)" ] && [ -n "$(OIDC_ISSUER_URL)" ] && [ -n "$(VAULT_DOMAIN)" ]; then \
	  echo "$(YELLOW)→ Configuring Vault OIDC...$(RESET)"; \
	  $(K) exec -n vault $(VAULT_POD) -- \
	    env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault auth list -format=json 2>/dev/null \
	    | python3 -c "import sys,json; sys.exit(0 if 'oidc/' in json.load(sys.stdin) else 1)" 2>/dev/null \
	    || $(K) exec -n vault $(VAULT_POD) -- \
	      env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault auth enable oidc; \
	  $(K) exec -n vault $(VAULT_POD) -- \
	    env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault write auth/oidc/config \
	      oidc_discovery_url="$(OIDC_ISSUER_URL)" \
	      oidc_client_id="$(OIDC_CLIENT_ID)" \
	      oidc_client_secret="$(OIDC_CLIENT_SECRET)" \
	      default_role="default"; \
	  printf 'path "secret/*" {\n  capabilities = ["create","read","update","delete","list"]\n}\npath "secret/data/*" {\n  capabilities = ["create","read","update","delete","list"]\n}\npath "secret/metadata/*" {\n  capabilities = ["read","list","delete"]\n}\npath "sys/health" {\n  capabilities = ["read","sudo"]\n}\npath "sys/seal-status" {\n  capabilities = ["read"]\n}\npath "sys/policies/*" {\n  capabilities = ["read","list"]\n}\npath "auth/*" {\n  capabilities = ["read","list"]\n}\n' \
	    | $(K) exec -i -n vault $(VAULT_POD) -- \
	      env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault policy write vault-admin -; \
	  $(K) exec -n vault $(VAULT_POD) -- \
	    env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) vault write auth/oidc/role/default \
	      user_claim="email" \
	      allowed_redirect_uris="https://$(VAULT_DOMAIN)/ui/vault/auth/oidc/oidc/callback" \
	      allowed_redirect_uris="http://localhost:8250/oidc/callback" \
	      policies="default,vault-admin" \
	      oidc_scopes="openid,email,profile" \
	      ttl=12h; \
	fi
	@echo "$(GREEN)✅ Vault configured$(RESET)"

vault-seed: ## Seed secrets into Vault (reads from .env, prompts only if missing)
	@[ -n "$(VAULT_ROOT_TOKEN)" ] || (echo "$(RED)❌ VAULT_ROOT_TOKEN not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Seeding secrets into Vault...$(RESET)"
	@echo ""
	@_oidc_id="$(OIDC_CLIENT_ID)"; \
	 _oidc_secret="$(OIDC_CLIENT_SECRET)"; \
	 [ -z "$$_oidc_id" ] && read -p "  OIDC_CLIENT_ID    : " _oidc_id < /dev/tty; \
	 [ -z "$$_oidc_secret" ] && read -p "  OIDC_CLIENT_SECRET: " _oidc_secret < /dev/tty; \
	 [ -n "$$_oidc_id" ] && \
	   $(K) exec -n vault $(VAULT_POD) -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/argocd/oidc \
	       clientID="$$_oidc_id" \
	       clientSecret="$$_oidc_secret" \
	  && echo "  ✓ argocd/oidc" \
	  || echo "  (skipped argocd/oidc)"
	@echo ""
	@_grafana_pw="$(GRAFANA_PASSWORD)"; \
	 [ -z "$$_grafana_pw" ] && read -p "  GRAFANA_PASSWORD  : " _grafana_pw < /dev/tty; \
	 [ -n "$$_grafana_pw" ] && \
	   $(K) exec -n vault $(VAULT_POD) -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/grafana/admin \
	       username="admin" \
	       password="$$_grafana_pw" \
	  && echo "  ✓ grafana/admin" \
	  || echo "  (skipped grafana/admin)"
	@echo ""
	@_gf_id="$(OIDC_CLIENT_ID)"; \
	 _gf_sec="$(OIDC_CLIENT_SECRET)"; \
	 _gf_auth_url="$(OIDC_AUTH_URL)"; \
	 _gf_token_url="$(OIDC_TOKEN_URL)"; \
	 _gf_api_url="$(OIDC_API_URL)"; \
	 [ -z "$$_gf_id" ] && read -p "  OIDC_CLIENT_ID    : " _gf_id < /dev/tty; \
	 [ -z "$$_gf_sec" ] && read -p "  OIDC_CLIENT_SECRET: " _gf_sec < /dev/tty; \
	 [ -z "$$_gf_auth_url" ] && read -p "  OIDC_AUTH_URL     : " _gf_auth_url < /dev/tty; \
	 [ -z "$$_gf_token_url" ] && read -p "  OIDC_TOKEN_URL    : " _gf_token_url < /dev/tty; \
	 [ -z "$$_gf_api_url" ] && read -p "  OIDC_API_URL      : " _gf_api_url < /dev/tty; \
	 [ -n "$$_gf_id" ] && \
	   $(K) exec -n vault $(VAULT_POD) -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/grafana/oauth \
	       GF_AUTH_GENERIC_OAUTH_ENABLED="true" \
	       GF_AUTH_GENERIC_OAUTH_NAME="$(OIDC_PROVIDER_NAME)" \
	       GF_AUTH_GENERIC_OAUTH_CLIENT_ID="$$_gf_id" \
	       GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="$$_gf_sec" \
	       GF_AUTH_GENERIC_OAUTH_SCOPES="openid email profile" \
	       GF_AUTH_GENERIC_OAUTH_AUTH_URL="$$_gf_auth_url" \
	       GF_AUTH_GENERIC_OAUTH_TOKEN_URL="$$_gf_token_url" \
	       GF_AUTH_GENERIC_OAUTH_API_URL="$$_gf_api_url" \
	       GF_AUTH_GENERIC_OAUTH_USE_PKCE="true" \
	       GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN="true" \
	       GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN="true" \
	       GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP="true" \
	       GF_AUTH_DISABLE_LOGIN_FORM="true" \
	  && echo "  ✓ grafana/oauth" \
	  || echo "  (skipped grafana/oauth)"
	@echo ""
	@_dash_users="$(DASHBOARD_USERS)"; \
	 if [ -z "$$_dash_users" ] && [ -n "$(DASHBOARD_PASSWORD)" ]; then \
	   _dash_users=$$(htpasswd -nb "$(DASHBOARD_USER)" "$(DASHBOARD_PASSWORD)" 2>/dev/null \
	     || printf '%s:%s\n' "$(DASHBOARD_USER)" "$$(openssl passwd -apr1 "$(DASHBOARD_PASSWORD)")"); \
	 fi; \
	 [ -z "$$_dash_users" ] && read -p "  DASHBOARD_USERS (htpasswd): " _dash_users < /dev/tty; \
	 [ -n "$$_dash_users" ] && \
	   $(K) exec -n vault $(VAULT_POD) -- \
	     env VAULT_TOKEN=$(VAULT_ROOT_TOKEN) \
	     vault kv put secret/traefik/dashboard \
	       users="$$_dash_users" \
	  && echo "  ✓ traefik/dashboard" \
	  || echo "  (skipped traefik/dashboard)"
	@echo ""
	@echo "$(GREEN)✅ Vault secrets seeded$(RESET)"

vault-status: ## Show Vault seal status, ESO sync status, and managed secrets
	@echo ""
	@echo "$(CYAN)── Vault ────────────────────────────────────────────────────────$(RESET)"
	@$(K) exec -n vault $(VAULT_POD) -- \
	  vault status 2>/dev/null || echo "$(RED)❌ Vault pod not reachable$(RESET)"
	@echo ""
	@echo "$(CYAN)── External Secrets (sync status) ──────────────────────────────$(RESET)"
	@$(K) get externalsecrets -A \
	  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,REFRESH:.status.refreshTime' \
	  2>/dev/null || echo "$(RED)❌ ESO not installed or no ExternalSecrets found$(RESET)"
	@echo ""
	@echo "$(CYAN)── ClusterSecretStore ───────────────────────────────────────────$(RESET)"
	@$(K) get clustersecretstore \
	  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[0].status' \
	  2>/dev/null || echo "  (none)"
	@echo ""
