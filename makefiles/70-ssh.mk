# Module: makefiles/70-ssh.mk
# ──────────────────────────────────────────────────────────────────────────────
# SSH
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: ssh-server ssh-agent known-hosts-reset

ssh-server: ## Open SSH shell on server
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP is not set$(RESET)"; exit 1)
	@echo "$(CYAN)→ Connecting to server $(SERVER_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP)

ssh-agent: ## Open SSH shell on agent
	@[ -n "$(AGENT_IP)" ] || (echo "$(RED)❌ AGENT_IP is not set$(RESET)"; exit 1)
	@echo "$(CYAN)→ Connecting to agent $(AGENT_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(AGENT_IP)

known-hosts-reset: ## Remove stale known_hosts entries for server and agent (run after VPS reformat)
	@echo "$(YELLOW)→ Removing stale host keys...$(RESET)"
	@[ -z "$(SERVER_IP)" ] || ssh-keygen -R "$(SERVER_IP)" 2>/dev/null; true
	@[ -z "$(AGENT_IP)" ] || ssh-keygen -R "$(AGENT_IP)" 2>/dev/null; true
	@echo "$(GREEN)✅ known_hosts cleaned$(RESET)"
