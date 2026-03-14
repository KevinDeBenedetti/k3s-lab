# Module: makefiles/70-ssh.mk
# ──────────────────────────────────────────────────────────────────────────────
# SSH
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: ssh-master ssh-worker known-hosts-reset

ssh-master: ## Open SSH shell on master
	@[ -n "$(MASTER_IP)" ] || (echo "$(RED)❌ MASTER_IP is not set$(RESET)"; exit 1)
	@echo "$(CYAN)→ Connecting to master $(MASTER_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(MASTER_IP)

ssh-worker: ## Open SSH shell on worker
	@[ -n "$(WORKER_IP)" ] || (echo "$(RED)❌ WORKER_IP is not set$(RESET)"; exit 1)
	@echo "$(CYAN)→ Connecting to worker $(WORKER_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(WORKER_IP)

known-hosts-reset: ## Remove stale known_hosts entries for master and worker (run after VPS reformat)
	@echo "$(YELLOW)→ Removing stale host keys...$(RESET)"
	@[ -z "$(MASTER_IP)" ] || ssh-keygen -R "$(MASTER_IP)" 2>/dev/null; true
	@[ -z "$(WORKER_IP)" ] || ssh-keygen -R "$(WORKER_IP)" 2>/dev/null; true
	@echo "$(GREEN)✅ known_hosts cleaned$(RESET)"
