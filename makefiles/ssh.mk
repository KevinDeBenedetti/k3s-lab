# Module: makefiles/ssh.mk
# ──────────────────────────────────────────────────────────────────────────────
# SSH
# ──────────────────────────────────────────────────────────────────────────────

# SSH_SERVER_HOST: override in the consuming Makefile to change where
# ssh-server connects (e.g. via WireGuard instead of public IP).
# Default: public SERVER_IP.
SSH_SERVER_HOST ?= $(SERVER_IP)

.PHONY: ssh-server ssh-agent known-hosts-reset

ssh-server: ## Open SSH shell on server
	@[ -n "$(SSH_SERVER_HOST)" ] || (echo "$(RED)❌ SERVER_IP is not set$(RESET)"; exit 1)
	@echo "$(CYAN)→ Connecting to server $(SSH_SERVER_HOST)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SSH_SERVER_HOST)

ssh-agent: ## Open SSH shell on agent
	@[ -n "$(AGENT_IP)" ] || (echo "$(RED)❌ AGENT_IP is not set$(RESET)"; exit 1)
	@echo "$(CYAN)→ Connecting to agent $(AGENT_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(AGENT_IP)

known-hosts-reset: ## Remove stale known_hosts entries for server and agent (run after VPS reformat)
	@echo "$(YELLOW)→ Removing stale host keys...$(RESET)"
	@[ -z "$(SERVER_IP)" ] || ssh-keygen -R "$(SERVER_IP)" 2>/dev/null; true
	@[ -z "$(AGENT_IP)" ] || ssh-keygen -R "$(AGENT_IP)" 2>/dev/null; true
	@echo "$(GREEN)✅ known_hosts cleaned$(RESET)"
