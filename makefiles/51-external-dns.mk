# Module: makefiles/51-external-dns.mk
# ──────────────────────────────────────────────────────────────────────────────
# external-dns — Automatic Cloudflare DNS record management
#
# external-dns is deployed via ArgoCD. These targets provide operational
# visibility into the running deployment.
#
# Usage:
#   make external-dns-status     — show pod status + recent log lines
#   make external-dns-logs       — tail live logs
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: external-dns-status external-dns-logs

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
