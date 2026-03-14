# Module: makefiles/30-k3s.mk
# ──────────────────────────────────────────────────────────────────────────────
# k3s Installation
# Uses run-remote-script from 00-lib.mk (local scp or remote curl, transparent).
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: k3s-master k3s-worker k3s-open-master-firewall k3s-uninstall-master k3s-uninstall-worker

k3s-master: ## Install k3s server on master (requires MASTER_IP)
	@[ -n "$(MASTER_IP)" ] || (echo "$(RED)❌ MASTER_IP is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Installing k3s master on $(MASTER_IP)...$(RESET)"
	@$(call run-remote-script,k3s/install-master.sh,$(MASTER_IP),sudo K3S_VERSION=$(K3S_VERSION) PUBLIC_IP=$(MASTER_IP) WORKER_IP=$(WORKER_IP))
	@echo "$(GREEN)✅ k3s master installed$(RESET)"
	@echo "$(YELLOW)→ Fetching node token and saving to .env...$(RESET)"
	@TOKEN=$$(ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(MASTER_IP) \
		"sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null"); \
	if [ -n "$$TOKEN" ]; then \
		sed -i.bak "s|^K3S_NODE_TOKEN=.*|K3S_NODE_TOKEN=$$TOKEN|" .env && rm -f .env.bak; \
		echo "$(GREEN)✅ K3S_NODE_TOKEN saved to .env$(RESET)"; \
	else \
		echo "$(RED)⚠️  Could not read node token — set K3S_NODE_TOKEN manually in .env$(RESET)"; \
	fi

k3s-worker: ## Install k3s agent on worker (requires WORKER_IP, MASTER_IP, K3S_NODE_TOKEN)
	@[ -n "$(WORKER_IP)" ]      || (echo "$(RED)❌ WORKER_IP is not set — pass via: make k3s-worker WORKER_IP=x.x.x.x$(RESET)"; exit 1)
	@[ -n "$(MASTER_IP)" ]      || (echo "$(RED)❌ MASTER_IP is not set$(RESET)"; exit 1)
	@[ -n "$(K3S_NODE_TOKEN)" ] || (echo "$(RED)❌ K3S_NODE_TOKEN is not set — run make k3s-master first$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Opening master firewall for new worker $(WORKER_IP)...$(RESET)"
	@$(MAKE) k3s-open-master-firewall WORKER_IP=$(WORKER_IP)
	@echo "$(YELLOW)→ Installing k3s worker on $(WORKER_IP)...$(RESET)"
	@$(call run-remote-script,k3s/install-worker.sh,$(WORKER_IP),sudo K3S_VERSION=$(K3S_VERSION) MASTER_IP=$(MASTER_IP) K3S_NODE_TOKEN=$(K3S_NODE_TOKEN))
	@echo "$(GREEN)✅ k3s worker installed$(RESET)"

k3s-open-master-firewall: ## Open master UFW for a new worker (requires WORKER_IP, MASTER_IP)
	@[ -n "$(WORKER_IP)" ] || (echo "$(RED)❌ WORKER_IP is not set$(RESET)"; exit 1)
	@[ -n "$(MASTER_IP)" ] || (echo "$(RED)❌ MASTER_IP is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Adding UFW rules on master for worker $(WORKER_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(MASTER_IP) \
		"sudo ufw allow from $(WORKER_IP) to any port 8472 proto udp comment 'flannel VXLAN from worker $(WORKER_IP)' && \
		 sudo ufw allow from $(WORKER_IP) to any port 10250 proto tcp comment 'k3s kubelet from worker $(WORKER_IP)' && \
		 sudo ufw reload"
	@echo "$(GREEN)✅ Master firewall updated for worker $(WORKER_IP)$(RESET)"

k3s-uninstall-master: ## Remove k3s from master (DESTRUCTIVE)
	@[ -n "$(MASTER_IP)" ] || (echo "$(RED)❌ MASTER_IP is not set$(RESET)"; exit 1)
	@echo "$(RED)⚠️  Removing k3s from master $(MASTER_IP)...$(RESET)"
	@$(call run-remote-script,k3s/uninstall.sh,$(MASTER_IP),sudo)

k3s-uninstall-worker: ## Remove k3s from worker (DESTRUCTIVE)
	@[ -n "$(WORKER_IP)" ] || (echo "$(RED)❌ WORKER_IP is not set$(RESET)"; exit 1)
	@echo "$(RED)⚠️  Removing k3s from worker $(WORKER_IP)...$(RESET)"
	@$(call run-remote-script,k3s/uninstall.sh,$(WORKER_IP),sudo)
