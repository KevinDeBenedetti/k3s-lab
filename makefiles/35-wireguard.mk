# Module: makefiles/35-wireguard.mk
# ──────────────────────────────────────────────────────────────────────────────
# WireGuard admin VPN — manage a WireGuard server on the k3s server VPS.
# Uses run-remote-script from 00-lib.mk (local scp or remote curl, transparent).
#
# Flow:
#   1. make wg-server-up               — install + configure + start wg0
#   2. make wg-client-config           — generate client keypair + add peer + print .conf
#      (or: make wg-peer-add WG_CLIENT_PUBKEY=<key>  if you have your own keys)
#   3. make wg-up                      — connect: wg-quick up wg0 (client)
#   4. make wg-status                  — verify handshake
#
# Required vars:  SERVER_IP, SSH_USER, SSH_KEY, SSH_PORT
# Optional vars:  WG_PORT (51820), WG_SERVER_IP (10.8.0.1), WG_SUBNET (10.8.0.0/24),
#                 WG_CLIENT_IP (10.8.0.2), WG_PEER_NAME (laptop)
# ──────────────────────────────────────────────────────────────────────────────

# Defaults (can be overridden in .env or on the command line)
WG_PORT         ?= 51820
WG_SERVER_IP    ?= 10.8.0.1
WG_SUBNET       ?= 10.8.0.0/24
WG_CLIENT_IP    ?= 10.8.0.2
WG_CLIENT_PUBKEY ?=
WG_PEER_NAME    ?= laptop

.PHONY: wg-server-up wg-peer-add wg-client-config wg-status wg-down \
        wg-up wg-disconnect wg-ssh-harden kubeconfig-vpn

wg-server-up: ## Install WireGuard and start wg0 on server (idempotent — safe to re-run)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Setting up WireGuard server on $(SERVER_IP)...$(RESET)"
	@$(call run-remote-script,scripts/wireguard/setup-server.sh,$(SERVER_IP),sudo WG_SERVER_IP=$(WG_SERVER_IP) WG_PORT=$(WG_PORT) WG_SUBNET=$(WG_SUBNET))
	@echo "$(GREEN)✅ WireGuard server ready$(RESET)"

wg-peer-add: ## Add a peer to the WireGuard server (requires WG_CLIENT_PUBKEY)
	@[ -n "$(SERVER_IP)" ]        || (echo "$(RED)❌ SERVER_IP not set$(RESET)"; exit 1)
	@[ -n "$(WG_CLIENT_PUBKEY)" ] || (echo "$(RED)❌ WG_CLIENT_PUBKEY not set — e.g. make wg-peer-add WG_CLIENT_PUBKEY=<base64> WG_CLIENT_IP=10.8.0.2$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Adding peer '$(WG_PEER_NAME)' ($(WG_CLIENT_IP)) to server...$(RESET)"
	@$(call run-remote-script,scripts/wireguard/add-peer.sh,$(SERVER_IP),WG_CLIENT_PUBKEY='$(WG_CLIENT_PUBKEY)' WG_CLIENT_IP=$(WG_CLIENT_IP) WG_PEER_NAME=$(WG_PEER_NAME))
	@echo "$(GREEN)✅ Peer '$(WG_PEER_NAME)' added$(RESET)"

wg-client-config: ## Generate a client keypair locally, add it as peer, and print the .conf
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP not set$(RESET)" >&2; exit 1)
	@which wg >/dev/null 2>&1 || (echo "$(RED)❌ wg not found — brew install wireguard-tools$(RESET)" >&2; exit 1)
	@$(eval CLIENT_KEY  := $(shell wg genkey))
	@$(eval CLIENT_PUB  := $(shell echo "$(CLIENT_KEY)" | wg pubkey))
	@$(eval SERVER_PUB  := $(shell ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) "sudo cat /etc/wireguard/server.pub"))
	@$(MAKE) --no-print-directory wg-peer-add \
		WG_CLIENT_PUBKEY="$(CLIENT_PUB)" \
		WG_CLIENT_IP="$(WG_CLIENT_IP)" \
		WG_PEER_NAME="$(WG_PEER_NAME)" >&2
	@# ── Only the valid INI config block goes to stdout (safe to redirect to file) ──
	@echo "[Interface]"
	@echo "PrivateKey = $(CLIENT_KEY)"
	@echo "Address    = $(WG_CLIENT_IP)/32"
	@echo "DNS        = 1.1.1.1"
	@echo ""
	@echo "[Peer]"
	@echo "PublicKey           = $(SERVER_PUB)"
	@echo "Endpoint            = $(SERVER_IP):$(WG_PORT)"
	@echo "AllowedIPs          = $(WG_SUBNET)"
	@echo "PersistentKeepalive = 25"
	@echo "$(CYAN)✅ Config printed above — run to save it:$(RESET)" >&2
	@echo "  make wg-client-config WG_PEER_NAME=$(WG_PEER_NAME) > \"\$$(brew --prefix)/etc/wireguard/wg0.conf\"" >&2
	@echo "  chmod 600 \"\$$(brew --prefix)/etc/wireguard/wg0.conf\"" >&2
	@echo "  sudo wg-quick up wg0" >&2

wg-status: ## Show live WireGuard peers and handshake times on server
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP not set$(RESET)"; exit 1)
	@_HOST=$(SERVER_IP); \
	if ssh -i $(SSH_KEY) -p $(SSH_PORT) -o ConnectTimeout=3 $(SSH_USER)@$(WG_SERVER_IP) true 2>/dev/null; then \
		_HOST=$(WG_SERVER_IP); \
	fi; \
	echo "$(CYAN)→ Connecting to $$_HOST...$(RESET)"; \
	ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$$_HOST "sudo wg show"

wg-down: ## Stop WireGuard on server (run wg-server-up to restart)
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP not set$(RESET)"; exit 1)
	@echo "$(YELLOW)→ Stopping wg-quick@wg0...$(RESET)"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) "sudo systemctl stop wg-quick@wg0"
	@echo "$(GREEN)✅ WireGuard stopped$(RESET)"

wg-up: ## [macOS] Connect to WireGuard VPN (requires wg-quick + wg0.conf)
	@which wg-quick >/dev/null 2>&1 || (echo "$(RED)❌ wg-quick not found — brew install wireguard-tools$(RESET)"; exit 1)
	@if ifconfig utun6 >/dev/null 2>&1 || ifconfig wg0 >/dev/null 2>&1; then \
		echo "$(YELLOW)→ WireGuard already connected ($(WG_CLIENT_IP))$(RESET)"; \
	else \
		sudo wg-quick up wg0 && echo "$(GREEN)✅ WireGuard connected — tunnel IP: $(WG_CLIENT_IP)$(RESET)"; \
	fi

wg-disconnect: ## [macOS] Disconnect from WireGuard VPN
	@sudo wg-quick down wg0 2>/dev/null && echo "$(GREEN)✅ WireGuard disconnected$(RESET)" || echo "$(YELLOW)→ WireGuard already disconnected$(RESET)"

wg-ssh-harden: ## Restrict SSH on server to WireGuard subnet only — AFTER confirming VPN works
	@[ -n "$(SERVER_IP)" ] || (echo "$(RED)❌ SERVER_IP not set$(RESET)"; exit 1)
	@echo "$(RED)⚠️  This will block SSH from all IPs except $(WG_SUBNET). Ensure VPN is connected first.$(RESET)"
	@echo "$(YELLOW)→ Connect to VPN then re-run: make wg-ssh-harden CONFIRM=yes$(RESET)"
	@[ "$(CONFIRM)" = "yes" ] || (echo "$(RED)❌ Aborted — pass CONFIRM=yes to proceed$(RESET)"; exit 1)
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) \
		"sudo ufw allow from $(WG_SUBNET) to any port $(SSH_PORT) proto tcp comment 'SSH via WireGuard'"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) \
		"sudo ufw delete allow $(SSH_PORT)/tcp 2>/dev/null || true"
	@ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_USER)@$(SERVER_IP) \
		"sudo ufw deny $(SSH_PORT)/tcp comment 'Block public SSH' && sudo ufw reload"
	@echo "$(GREEN)✅ SSH restricted to WireGuard subnet $(WG_SUBNET)$(RESET)"
	@echo "$(YELLOW)→ From now on: connect VPN first, then SSH via $(WG_SERVER_IP)$(RESET)"
	@echo "     ssh -i $(SSH_KEY) $(SSH_USER)@$(WG_SERVER_IP)"

kubeconfig-vpn: ## Switch kubeconfig server address to WireGuard IP (kubectl works only when VPN is on)
	@echo "$(YELLOW)→ Patching context '$(KUBECONFIG_CONTEXT)' to use WireGuard IP $(WG_SERVER_IP)...$(RESET)"
	@kubectl config set-cluster $(KUBECONFIG_CONTEXT) \
		--server=https://$(WG_SERVER_IP):6443
	@echo "$(GREEN)✅ kubectl now routes through WireGuard (connect VPN before using kubectl)$(RESET)"
	@echo "$(YELLOW)→ To revert to public IP: make kubeconfig$(RESET)"
