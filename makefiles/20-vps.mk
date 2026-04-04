# Module: makefiles/20-vps.mk
# ──────────────────────────────────────────────────────────────────────────────
# VPS Bootstrap — runs dotfiles setup on a fresh Debian VPS
# Uses run-local-script from 00-lib.mk (local bash or remote curl, transparent).
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: setup-server setup-agent setup-all

setup-server: ## Bootstrap server VPS with dotfiles (requires SERVER_IP)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP is not set — add it to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Setting up server VPS $(SERVER_IP) as $(INITIAL_USER)...$(RESET)"
	@$(call run-local-script,scripts/setup-vps.sh,$(SERVER_IP) $(SSH_USER) $(SSH_PORT) $(INITIAL_USER))

setup-agent: ## Bootstrap agent VPS with dotfiles (requires AGENT_IP)
	@[ -n "$(AGENT_IP)" ] || (echo "$(RED)❌ AGENT_IP is not set — add it to .env$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Setting up agent VPS $(AGENT_IP) as $(INITIAL_USER)...$(RESET)"
	@$(call run-local-script,scripts/setup-vps.sh,$(AGENT_IP) $(SSH_USER) $(SSH_PORT) $(INITIAL_USER))

setup-all: setup-server setup-agent ## Bootstrap both VPS nodes with dotfiles
