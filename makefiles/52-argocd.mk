# Module: makefiles/52-argocd.mk
# ──────────────────────────────────────────────────────────────────────────────
# ArgoCD — GitOps Continuous Delivery
#
# Deploys ArgoCD via Helm using Traefik for ingress and cert-manager for TLS.
# The UI and gRPC are VPN-only; the GitHub webhook endpoint stays public.
#
# Manifests used (resolved relative to make CWD):
#   kubernetes/argocd/helm-values.yaml    — Helm chart overrides
#   kubernetes/argocd/ingressroute.yaml   — Traefik IngressRoute + TLS cert
#   kubernetes/argocd/middleware-vpn-only.yaml — WireGuard subnet restriction
#
# Consuming repos (e.g. infra) can override helm-values.yaml by providing
# their own copy at kubernetes/argocd/helm-values.yaml (path resolution wins).
# ──────────────────────────────────────────────────────────────────────────────

ARGOCD_VERSION          ?= 7.8.26
ARGOCD_DOMAIN           ?=
ARGOCD_REPO_URL         ?=
ARGOCD_REPO_SECRET_NAME ?= argocd-repo
# ADMIN_EMAIL is shared with other modules (e.g. 55-vault.mk RBAC allow-list).
ADMIN_EMAIL             ?=

.PHONY: deploy-argocd argocd-add-repo argocd-deploy-apps \
        argocd-status argocd-password argocd-delete-initial-secret argocd-disable-admin

deploy-argocd: ## Deploy ArgoCD (run after make deploy)
	@[ -n "$(ARGOCD_DOMAIN)" ] || (echo "$(RED)❌ ARGOCD_DOMAIN not set — add to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Deploying ArgoCD $(ARGOCD_VERSION)...$(RESET)"
	@helm repo add argo https://argoproj.github.io/argo-helm --force-update
	@helm repo update argo
	@helm upgrade --install argocd argo/argo-cd \
		--version "$(ARGOCD_VERSION)" \
		--namespace argocd \
		--create-namespace \
		--values kubernetes/argocd/helm-values.yaml \
		--set "global.domain=$(ARGOCD_DOMAIN)" \
		--set "configs.cm.url=https://$(ARGOCD_DOMAIN)" \
		--wait \
		--timeout 300s
	@kubectl --context $(KUBECONFIG_CONTEXT) apply \
		-f kubernetes/argocd/middleware-vpn-only.yaml
	@ARGOCD_DOMAIN=$(ARGOCD_DOMAIN) envsubst < kubernetes/argocd/ingressroute.yaml \
		| kubectl --context $(KUBECONFIG_CONTEXT) apply -f -
	@echo ""
	@echo "$(GREEN)✅ ArgoCD deployed$(RESET)"
	@echo ""
	@echo "  UI:       https://$(ARGOCD_DOMAIN)"
	@echo "  User:     admin"
	@echo "  Password: $$(kubectl --context $(KUBECONFIG_CONTEXT) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(secret already deleted)')"
	@echo ""
	@echo "$(YELLOW)Next steps:$(RESET)"
	@echo "  1. Add DNS: $(ARGOCD_DOMAIN) → $(SERVER_IP)"
	@echo "  2. Register Git repo:  make argocd-add-repo ARGOCD_REPO_URL=git@github.com:you/infra.git GITHUB_DEPLOY_KEY=~/.ssh/deploy_key"
	@echo "  3. Apply apps:         make argocd-deploy-apps"
	@echo "  4. Add GitHub webhook: https://$(ARGOCD_DOMAIN)/api/webhook"

argocd-add-repo: ## Register a Git repo in ArgoCD via SSH deploy key (requires ARGOCD_REPO_URL + GITHUB_DEPLOY_KEY)
	@[ -n "$(ARGOCD_REPO_URL)" ] || (echo "$(RED)❌ ARGOCD_REPO_URL not set — e.g. git@github.com:you/infra.git$(RESET)"; exit 1)
	@[ -n "$(GITHUB_DEPLOY_KEY)" ] || (echo "$(RED)❌ GITHUB_DEPLOY_KEY not set — e.g. ~/.ssh/deploy_key$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Registering $(ARGOCD_REPO_URL) in ArgoCD...$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) create secret generic $(ARGOCD_REPO_SECRET_NAME) \
		--from-literal=type=git \
		--from-literal=url=$(ARGOCD_REPO_URL) \
		--from-file=sshPrivateKey="$(GITHUB_DEPLOY_KEY)" \
		--namespace argocd \
		--dry-run=client -o yaml \
		| kubectl --context $(KUBECONFIG_CONTEXT) apply -f -
	@kubectl --context $(KUBECONFIG_CONTEXT) label secret $(ARGOCD_REPO_SECRET_NAME) \
		-n argocd argocd.argoproj.io/secret-type=repository --overwrite
	@echo "$(GREEN)✅ Repo registered$(RESET)"

argocd-deploy-apps: ## Apply all ArgoCD Application manifests from kubernetes/argocd/apps/
	@echo "$(YELLOW)→ Applying ArgoCD Applications...$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) apply -f kubernetes/argocd/apps/
	@echo "$(GREEN)✅ Applications submitted$(RESET)"
	@echo ""
	@kubectl --context $(KUBECONFIG_CONTEXT) get applications -n argocd

argocd-status: ## Show ArgoCD app sync and health status
	@echo "$(CYAN)── ArgoCD Applications ─────────────────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) get applications -n argocd \
		-o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REPO:.spec.source.repoURL' \
		2>/dev/null || echo "  $(RED)❌ ArgoCD not reachable$(RESET)"

argocd-password: ## Print the initial ArgoCD admin password
	@echo "$(YELLOW)⚠️  Delete this secret after first login: make argocd-delete-initial-secret$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo \
		|| echo "$(GREEN)✅ argocd-initial-admin-secret already deleted$(RESET)"

argocd-delete-initial-secret: ## Delete argocd-initial-admin-secret (run after first OIDC login)
	@echo "$(YELLOW)→ Deleting argocd-initial-admin-secret...$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) -n argocd delete secret argocd-initial-admin-secret \
		--ignore-not-found
	@echo "$(GREEN)✅ Initial admin secret deleted$(RESET)"

argocd-disable-admin: ## Disable ArgoCD local admin user (safe once OIDC is confirmed working)
	@echo "$(YELLOW)→ Disabling ArgoCD local admin user...$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) -n argocd patch configmap argocd-cm \
		--type=merge -p '{"data":{"admin.enabled":"false"}}'
	@echo "$(GREEN)✅ Local admin disabled — OIDC is now the only login method$(RESET)"
	@echo "$(YELLOW)⚠️  To re-enable: kubectl -n argocd patch cm argocd-cm --type=merge -p '{\"data\":{\"admin.enabled\":\"true\"}}'$(RESET)"
