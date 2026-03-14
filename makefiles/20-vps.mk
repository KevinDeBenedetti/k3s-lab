# Module: makefiles/20-vps.mk
# ──────────────────────────────────────────────────────────────────────────────
# VPS Bootstrap — runs dotfiles setup on a fresh Debian VPS
# Uses run-local-script from 00-lib.mk (local bash or remote curl, transparent).
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: setup-master setup-worker setup-all

setup-master: ## Bootstrap master VPS with dotfiles (requires MASTER_IP)
	@[ -n "$(MASTER_IP)" ] || (echo "$(RED)❌ MASTER_IP is not set — add it to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Setting up master VPS $(MASTER_IP) as $(INITIAL_USER)...$(RESET)"
	@$(call run-local-script,scripts/setup-vps.sh,$(MASTER_IP) $(SSH_USER) $(SSH_PORT) $(INITIAL_USER))

setup-worker: ## Bootstrap worker VPS with dotfiles (requires WORKER_IP)
	@[ -n "$(WORKER_IP)" ] || (echo "$(RED)❌ WORKER_IP is not set — add it to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Setting up worker VPS $(WORKER_IP) as $(INITIAL_USER)...$(RESET)"
	@$(call run-local-script,scripts/setup-vps.sh,$(WORKER_IP) $(SSH_USER) $(SSH_PORT) $(INITIAL_USER))

setup-all: setup-master setup-worker ## Bootstrap both VPS nodes with dotfiles
