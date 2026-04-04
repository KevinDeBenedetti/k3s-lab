# Module: makefiles/30-k3s.mk
# ──────────────────────────────────────────────────────────────────────────────
# k3s Installation
# Uses run-remote-script from 00-lib.mk (local scp or remote curl, transparent).
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: k3s-server k3s-agent k3s-open-server-firewall k3s-uninstall-server k3s-uninstall-agent

k3s-server: ## Install k3s server on server (requires SERVER_IP)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Installing k3s server on $(SERVER_IP)...$(RESET)"
	@$(call run-remote-script,k3s/install-server.sh,$(SERVER_IP),sudo K3S_VERSION=$(K3S_VERSION) FLANNEL_BACKEND=$(or $(FLANNEL_BACKEND),vxlan) PUBLIC_IP=$(SERVER_IP) AGENT_IP=$(AGENT_IP) WG_PORT=$(WG_PORT))
	@echo "$(GREEN)✅ k3s server installed$(RESET)"
	@echo "$(YELLOW)→ Fetching node token and saving to .env...$(RESET)"
	@TOKEN=$$(ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) \
		"sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null"); \
	if [ -n "$$TOKEN" ]; then \
		sed -i.bak "s|^K3S_NODE_TOKEN=.*|K3S_NODE_TOKEN=$$TOKEN|" .env && rm -f .env.bak; \
		echo "$(GREEN)✅ K3S_NODE_TOKEN saved to .env$(RESET)"; \
	else \
		echo "$(RED)⚠️  Could not read node token — set K3S_NODE_TOKEN manually in .env$(RESET)"; \
	fi

k3s-agent: ## Install k3s agent on agent (requires AGENT_IP, SERVER_IP, K3S_NODE_TOKEN)
	@[ -n "$(AGENT_IP)" ]      || (echo "$(RED)❌ AGENT_IP is not set — pass via: make k3s-agent AGENT_IP=x.x.x.x$(RESET)"; exit 1)
	@[ -n "$(SERVER_IP)" ]     || (echo "$(RED)❌ SERVER_IP is not set$(RESET)"; exit 1)
	@[ -n "$(K3S_NODE_TOKEN)" ] || (echo "$(RED)❌ K3S_NODE_TOKEN is not set — run make k3s-server first$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Opening server firewall for new agent $(AGENT_IP)...$(RESET)"
	@$(MAKE) k3s-open-server-firewall AGENT_IP=$(AGENT_IP)
	@echo "$(YELLOW)→ Installing k3s agent on $(AGENT_IP)...$(RESET)"
	@$(call run-remote-script,k3s/install-agent.sh,$(AGENT_IP),sudo K3S_VERSION=$(K3S_VERSION) SERVER_IP=$(SERVER_IP) K3S_NODE_TOKEN=$(K3S_NODE_TOKEN))
	@echo "$(GREEN)✅ k3s agent installed$(RESET)"

k3s-open-server-firewall: ## Open server UFW for a new agent (requires AGENT_IP, SERVER_IP)
	@[ -n "$(AGENT_IP)" ]  || (echo "$(RED)❌ AGENT_IP is not set$(RESET)"; exit 1)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP is not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Adding UFW rules on server for agent $(AGENT_IP)...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) \
		"sudo ufw allow from $(AGENT_IP) to any port 8472 proto udp comment 'flannel VXLAN from agent $(AGENT_IP)' && \
		 sudo ufw allow from $(AGENT_IP) to any port 10250 proto tcp comment 'k3s kubelet from agent $(AGENT_IP)' && \
		 sudo ufw reload"
	@echo "$(GREEN)✅ Server firewall updated for agent $(AGENT_IP)$(RESET)"

k3s-uninstall-server: ## Remove k3s from server (DESTRUCTIVE)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP is not set$(RESET)"; exit 1)
	@echo "$(RED)⚠️  Removing k3s from server $(SERVER_IP)...$(RESET)"
	@$(call run-remote-script,k3s/uninstall.sh,$(SERVER_IP),sudo)

k3s-uninstall-agent: ## Remove k3s from agent (DESTRUCTIVE)
	@[ -n "$(AGENT_IP)" ] || (echo "$(RED)❌ AGENT_IP is not set$(RESET)"; exit 1)
	@echo "$(RED)⚠️  Removing k3s from agent $(AGENT_IP)...$(RESET)"
	@$(call run-remote-script,k3s/uninstall.sh,$(AGENT_IP),sudo)
