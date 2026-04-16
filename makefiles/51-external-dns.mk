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

deploy-external-dns: ## ⚠️ DEPRECATED — external-dns is now deployed via ArgoCD
	@echo "$(RED)❌ 'make deploy-external-dns' is deprecated.$(RESET)"
	@echo ""
	@echo "  external-dns should be managed via ArgoCD."
	@echo "  Add it as an ArgoCD Application or include it in an umbrella chart."
	@echo ""
	@exit 1

external-dns-status: ## Show external-dns pod status and recent log lines
	@echo ""
	@echo "$(CYAN)── external-dns ─────────────────────────────────────────────────$(RESET)"
	@$(K) get pods -n external-dns \
	  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp' \
	  2>/dev/null || echo "$(RED)❌ external-dns not installed$(RESET)"
	@echo ""
	@echo "$(CYAN)── Recent log (last 20 lines) ───────────────────────────────────$(RESET)"
	@$(K) logs -n external-dns \
	  deployment/external-dns --tail=20 2>/dev/null || true
	@echo ""

external-dns-logs: ## Tail external-dns logs (live)
	@$(K) logs -n external-dns \
	  deployment/external-dns -f
