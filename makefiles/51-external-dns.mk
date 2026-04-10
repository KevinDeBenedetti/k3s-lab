# Module: makefiles/51-external-dns.mk
# ──────────────────────────────────────────────────────────────────────────────
# external-dns — Automatic Cloudflare DNS record management
#
# Watches Ingress, Service and Traefik IngressRoute resources and creates/updates
# DNS A records in Cloudflare automatically.
#
# Usage:
#   make deploy-external-dns     — install / upgrade external-dns
#   make external-dns-status     — show pod status + recent log lines
#   make external-dns-logs       — tail live logs
# ──────────────────────────────────────────────────────────────────────────────

EXTERNAL_DNS_VERSION ?= 1.16.1

.PHONY: deploy-external-dns external-dns-status external-dns-logs

deploy-external-dns: ## Deploy external-dns (Cloudflare provider, traefik-proxy source)
	@[ -n "$(DOMAIN)" ] || (echo "$(RED)❌ DOMAIN not set — add to .env$(RESET)"; exit 1)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP not set — add to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Deploying external-dns $(EXTERNAL_DNS_VERSION)...$(RESET)"
	@EXTERNAL_DNS_VERSION=$(EXTERNAL_DNS_VERSION) \
	  $(call run-local-script,scripts/deploy-external-dns.sh)
	@echo "$(GREEN)✅ external-dns deployed$(RESET)"
	@echo "$(YELLOW)   Add annotation to IngressRoutes/Services to create DNS records:$(RESET)"
	@echo "     external-dns.alpha.kubernetes.io/hostname: app.$(DOMAIN)"

external-dns-status: ## Show external-dns pod status and recent log lines
	@echo ""
	@echo "$(CYAN)── external-dns ─────────────────────────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) get pods -n external-dns \
	  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp' \
	  2>/dev/null || echo "$(RED)❌ external-dns not installed$(RESET)"
	@echo ""
	@echo "$(CYAN)── Recent log (last 20 lines) ───────────────────────────────────$(RESET)"
	@kubectl --context $(KUBECONFIG_CONTEXT) logs -n external-dns \
	  deployment/external-dns --tail=20 2>/dev/null || true
	@echo ""

external-dns-logs: ## Tail external-dns logs (live)
	@kubectl --context $(KUBECONFIG_CONTEXT) logs -n external-dns \
	  deployment/external-dns -f
