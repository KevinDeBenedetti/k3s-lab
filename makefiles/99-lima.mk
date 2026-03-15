# Module: makefiles/99-lima.mk
# ──────────────────────────────────────────────────────────────────────────────
# Lima — Local VM testing
# Requires: brew install lima
# Docs:     tests/lima/debian-vps.yaml   (VPS setup verification)
#           tests/lima/k3s-master.yaml   (k3s master node)
# ──────────────────────────────────────────────────────────────────────────────

# Path to the local dotfiles repo (mounted read-only into Lima VMs at same path)
DOTFILES_DIR ?= $(HOME)/dev/dotfiles

VPS_VM_NAME    := infra-vps-vm
K3S_VM_NAME    := infra-k3s-vm
VPS_VM_CONFIG  := $(LIMA_TESTS_DIR)/debian-vps.yaml
K3S_VM_CONFIG  := $(LIMA_TESTS_DIR)/k3s-master.yaml
# Shared secret for local Lima k3s — not a real credential
K3S_LIMA_TOKEN ?= lima-local-test-token-k3s

# Lima uses GRAFANA_PASSWORD from .env if set, otherwise defaults to "admin"
# Override at call time: make vm-k3s-deploy-monitoring LIMA_GRAFANA_PASSWORD=mypass
LIMA_GRAFANA_PASSWORD ?= $(or $(GRAFANA_PASSWORD),admin)

# Shared pre-flight check used by Lima targets that require host context k3s-lima.
define require_k3s_lima
	@kubectl --context k3s-lima cluster-info --request-timeout=5s >/dev/null 2>&1 || \
		(echo "$(RED)❌ Cannot reach k3s-lima — run make vm-k3s-deploy first$(RESET)"; exit 1)
endef

.PHONY: vm-vps-create vm-vps-install vm-vps-test vm-vps-shell vm-vps-stop \
        vm-vps-start vm-vps-clean vm-vps-full \
        vm-k3s-create vm-k3s-install vm-k3s-kubeconfig vm-k3s-test \
        vm-k3s-shell vm-k3s-stop vm-k3s-start vm-k3s-clean vm-k3s-full \
        vm-k3s-deploy vm-k3s-deploy-monitoring \
        vm-k3s-smoke vm-k3s-smoke-monitoring vm-k3s-smoke-all

# ─── VPS VM (tests dotfiles kubernetes profile + VPS prerequisites) ───────────

vm-vps-create: ## [Lima] Create Debian 13 VPS simulation VM
	@echo "$(YELLOW)→ Creating VM '$(VPS_VM_NAME)'...$(RESET)"
	@limactl list $(VPS_VM_NAME) > /dev/null 2>&1 \
		&& echo "  ⚠️  VM already exists — run 'make vm-vps-clean' first" \
		|| limactl start --name=$(VPS_VM_NAME) --tty=false $(VPS_VM_CONFIG)
	@echo "$(GREEN)✅ VM '$(VPS_VM_NAME)' ready$(RESET)"

vm-vps-install: ## [Lima] Run dotfiles kubernetes profile inside VPS VM
	@echo "$(YELLOW)→ Running dotfiles kubernetes profile in '$(VPS_VM_NAME)'...$(RESET)"
	@limactl shell $(VPS_VM_NAME) bash -c \
		"sudo SUDO=sudo bash '$(DOTFILES_DIR)/os/debian/setup-kubernetes.sh'"
	@echo "$(GREEN)✅ Kubernetes profile applied$(RESET)"

vm-vps-test: ## [Lima] Verify VPS setup (kernel modules, sysctl, kubectl, helm)
	@echo "$(YELLOW)→ Verifying VPS setup in '$(VPS_VM_NAME)'...$(RESET)"
	@limactl shell $(VPS_VM_NAME) $(call lima-run-script,tests/scripts/verify-vps.sh)
	@echo "$(GREEN)✅ VPS verification done$(RESET)"

vm-vps-shell: ## [Lima] Open interactive shell in VPS VM
	@limactl shell $(VPS_VM_NAME)

vm-vps-stop: ## [Lima] Stop VPS VM (keep disk)
	@limactl stop $(VPS_VM_NAME)
	@echo "$(GREEN)✅ VM stopped$(RESET)"

vm-vps-start: ## [Lima] Start a stopped VPS VM
	@limactl start $(VPS_VM_NAME)
	@echo "$(GREEN)✅ VM started$(RESET)"

vm-vps-clean: ## [Lima] Delete VPS VM and free disk
	@echo "$(RED)→ Deleting VM '$(VPS_VM_NAME)'...$(RESET)"
	@limactl delete --force $(VPS_VM_NAME) 2>/dev/null || true
	@echo "$(GREEN)✅ VM deleted$(RESET)"

vm-vps-full: vm-vps-create vm-vps-install vm-vps-test ## [Lima] Full VPS cycle: create → install → verify
	@echo ""
	@echo "$(GREEN)🎉 VPS test cycle complete$(RESET)"

# ─── k3s VM (tests install-master.sh on a real k3s single-node cluster) ──────

vm-k3s-create: ## [Lima] Create k3s master VM (Debian 12, 4 GB RAM)
	@echo "$(YELLOW)→ Creating VM '$(K3S_VM_NAME)'...$(RESET)"
	@limactl list $(K3S_VM_NAME) > /dev/null 2>&1 \
		&& echo "  ⚠️  VM already exists — run 'make vm-k3s-clean' first" \
		|| limactl start --name=$(K3S_VM_NAME) --tty=false $(K3S_VM_CONFIG)
	@echo "$(GREEN)✅ VM '$(K3S_VM_NAME)' ready$(RESET)"

vm-k3s-install: ## [Lima] Run install-master.sh inside the k3s VM
	@echo "$(YELLOW)→ Installing k3s master in '$(K3S_VM_NAME)'...$(RESET)"
	@echo "  Token:     $(K3S_LIMA_TOKEN)"
	@echo "  PUBLIC_IP: 127.0.0.1 (port-forwarded to host)"
	@limactl shell $(K3S_VM_NAME) bash -c \
		"sudo K3S_NODE_TOKEN='$(K3S_LIMA_TOKEN)' PUBLIC_IP=127.0.0.1 $(call lima-run-script,k3s/install-master.sh)"
	@echo "$(GREEN)✅ k3s master installed$(RESET)"

vm-k3s-kubeconfig: ## [Lima] Merge k3s Lima kubeconfig → local context 'k3s-lima'
	@echo "$(YELLOW)→ Fetching kubeconfig from '$(K3S_VM_NAME)'...$(RESET)"
	@limactl shell $(K3S_VM_NAME) sudo cat /etc/rancher/k3s/k3s.yaml \
		| sed \
			-e 's|name: default|name: k3s-lima|g' \
			-e 's|cluster: default|cluster: k3s-lima|g' \
			-e 's|user: default|user: k3s-lima|g' \
			-e 's|current-context: default|current-context: k3s-lima|g' \
		> /tmp/k3s-lima.yaml
	@KUBECONFIG=/tmp/k3s-lima.yaml:$(HOME)/.kube/config kubectl config view --merge --flatten \
		> /tmp/k3s-merged.yaml
	@mv /tmp/k3s-merged.yaml $(HOME)/.kube/config && chmod 600 $(HOME)/.kube/config
	@rm -f /tmp/k3s-lima.yaml
	@echo "$(GREEN)✅ Context 'k3s-lima' merged$(RESET)"
	@echo "  kubectl config use-context k3s-lima"
	@echo "  kubectl --context k3s-lima get nodes"

vm-k3s-test: ## [Lima] Verify k3s node Ready + check pods + resource usage
	@echo "$(YELLOW)→ Verifying k3s cluster in '$(K3S_VM_NAME)'...$(RESET)"
	@echo "  Waiting 20s for system pods to reach Running state..."
	@sleep 20
	@limactl shell $(K3S_VM_NAME) sudo $(call lima-run-script,tests/scripts/verify-k3s.sh)
	@echo ""
	@echo "$(CYAN)→ Node status from host kubectl (context: k3s-lima):$(RESET)"
	@kubectl --context k3s-lima get nodes -o wide \
		|| echo "  ⚠️  kubectl --context k3s-lima failed — run 'make vm-k3s-kubeconfig' to refresh"
	@echo "$(GREEN)✅ k3s verification done$(RESET)"

vm-k3s-shell: ## [Lima] Open interactive shell in k3s VM
	@limactl shell $(K3S_VM_NAME)

vm-k3s-stop: ## [Lima] Stop k3s VM (keep disk + state)
	@limactl stop $(K3S_VM_NAME)
	@echo "$(GREEN)✅ VM stopped$(RESET)"

vm-k3s-start: ## [Lima] Start a stopped k3s VM
	@limactl start $(K3S_VM_NAME)
	@echo "$(GREEN)✅ VM started$(RESET)"

vm-k3s-clean: ## [Lima] Delete k3s VM and free disk (REMOVES CLUSTER DATA)
	@echo "$(RED)→ Deleting VM '$(K3S_VM_NAME)'...$(RESET)"
	@limactl delete --force $(K3S_VM_NAME) 2>/dev/null || true
	@echo "$(GREEN)✅ VM deleted$(RESET)"

vm-k3s-full: vm-k3s-create vm-k3s-install vm-k3s-kubeconfig vm-k3s-test ## [Lima] Full k3s cycle: create → install → kubeconfig → verify
	@echo ""
	@echo "$(GREEN)🎉 k3s test cycle complete$(RESET)"
	@echo "  kubectl config use-context k3s-lima"
	@echo "  make vm-k3s-deploy   to deploy base stack (Traefik + cert-manager)"
	@echo "  make vm-k3s-smoke    to run full TLS pipeline smoke test"
	@echo "  make vm-k3s-clean    to delete the VM"

vm-k3s-deploy: ## [Lima] Deploy base stack on Lima k3s (mirrors make deploy but uses k3s-lima context)
	@echo "$(YELLOW)→ Deploying base stack on Lima k3s cluster (context: k3s-lima)...$(RESET)"
	@kubectl --context k3s-lima cluster-info --request-timeout=5s >/dev/null 2>&1 || \
		(echo "$(RED)❌ Cannot reach k3s-lima — run make vm-k3s-full first$(RESET)"; exit 1)
	@kubectl config use-context k3s-lima
	@MASTER_IP=127.0.0.1 KUBECONFIG_CONTEXT=k3s-lima SKIP_DASHBOARD=true \
		TRAEFIK_EXTRA_ARGS="--set metrics.prometheus.serviceMonitor.enabled=false \
		  --set service.type=NodePort \
		  --set ports.web.nodePort=30080 \
		  --set ports.websecure.nodePort=30443 \
		  --set tlsOptions.default.sniStrict=false" \
		$(call run-local-script,scripts/deploy-stack.sh)
	@echo "$(GREEN)✅ Lima stack deployed — mirrors production deploy$(RESET)"
	@echo ""
	@echo "  Traefik:      curl -sk https://127.0.0.1:8443/ | head -c 200"
	@echo "  Full test:    make vm-k3s-smoke"
	@echo "  Monitoring:   make vm-k3s-deploy-monitoring"
	@echo "  Pods:         kubectl --context k3s-lima get pods -A"
	@echo "  Cleanup:      make vm-k3s-clean"

vm-k3s-deploy-monitoring: ## [Lima] Deploy full monitoring stack (Prometheus + Grafana + Loki + Promtail) on Lima k3s
	@echo "$(YELLOW)→ Deploying monitoring stack on Lima k3s (context: k3s-lima)...$(RESET)"
	$(require_k3s_lima)
	@echo "$(YELLOW)  [1/4] Creating monitoring namespace + Grafana admin secret...$(RESET)"
	@kubectl --context k3s-lima create namespace monitoring --dry-run=client -o yaml \
		| kubectl --context k3s-lima apply -f -
	@kubectl --context k3s-lima create secret generic grafana-admin-secret \
		--from-literal=username=admin \
		--from-literal=password="$(LIMA_GRAFANA_PASSWORD)" \
		-n monitoring \
		--dry-run=client -o yaml | kubectl --context k3s-lima apply -f -
	@echo "$(YELLOW)  [2/4] Deploying kube-prometheus-stack + Loki + Promtail...$(RESET)"
	@kubectl config use-context k3s-lima
	@KUBECONFIG_CONTEXT=k3s-lima \
		GRAFANA_DOMAIN=grafana.local \
		GRAFANA_PASSWORD="$(LIMA_GRAFANA_PASSWORD)" \
		$(call run-local-script,scripts/deploy-monitoring.sh)
	@echo "$(YELLOW)  [3/4] Syncing Grafana admin password (API via port-forward)...$(RESET)"
	@echo "  (avoids exec+grafana-cli which OOM-kills under the 200Mi container limit)"
	@kubectl --context k3s-lima port-forward -n monitoring svc/kube-prometheus-stack-grafana 13000:80 >/dev/null 2>&1 & \
		PF_PID=$$!; \
		sleep 3; \
		SYNCED=0; \
		for TRY in "$(LIMA_GRAFANA_PASSWORD)" prom-operator admin; do \
			CODE=$$(curl -s -o /dev/null -w '%{http_code}' \
				-X PUT http://localhost:13000/api/admin/users/1/password \
				-H "Content-Type: application/json" \
				-u "admin:$$TRY" \
				-d "{\"password\":\"$(LIMA_GRAFANA_PASSWORD)\"}"); \
			if [ "$$CODE" = "200" ]; then \
				echo "  ✓ Grafana admin password synced"; SYNCED=1; break; \
			fi; \
		done; \
		kill $$PF_PID 2>/dev/null; wait $$PF_PID 2>/dev/null || true; \
		[ "$$SYNCED" = "1" ] || echo "  ⚠  Could not sync password — reset manually in Grafana UI"
	@echo "$(YELLOW)  [4/4] Applying selfsigned TLS certificate for grafana.local...$(RESET)"
	@echo "  (overrides letsencrypt-production from grafana-ingress.yaml — not resolvable in Lima)"
	@kubectl --context k3s-lima apply -f $(LIMA_TESTS_DIR)/grafana-cert.yaml
	@kubectl --context k3s-lima wait certificate grafana-tls -n monitoring \
		--for=condition=Ready --timeout=60s
	@echo ""
	@echo "$(GREEN)✅ Monitoring stack deployed on Lima k3s$(RESET)"
	@echo ""
	@echo "$(CYAN)  Add to /etc/hosts (one-time):$(RESET)"
	@echo "    echo '127.0.0.1  grafana.local' | sudo tee -a /etc/hosts"
	@echo ""
	@echo "$(CYAN)  Open in browser (accept self-signed cert warning):$(RESET)"
	@echo "    https://grafana.local:8443"
	@echo "    Login: admin / $(LIMA_GRAFANA_PASSWORD)"
	@echo ""
	@echo "$(CYAN)  Port-forward Prometheus UI (optional):$(RESET)"
	@echo "    kubectl --context k3s-lima port-forward svc/prometheus-operated -n monitoring 9090:9090"
	@echo "    open http://localhost:9090"
	@echo ""
	@echo "$(CYAN)  Check pods:$(RESET)"
	@echo "    kubectl --context k3s-lima get pods -n monitoring"

vm-k3s-smoke: ## [Lima] Full TLS pipeline smoke test: cert-manager issues cert → Traefik serves it
	@echo "$(YELLOW)→ Running TLS pipeline smoke test on Lima k3s...$(RESET)"
	$(require_k3s_lima)
	@kubectl --context k3s-lima apply -f $(LIMA_TESTS_DIR)/smoke-test.yaml
	@echo "$(YELLOW)  Waiting for whoami pod to be ready...$(RESET)"
	@kubectl --context k3s-lima rollout status deployment/whoami -n apps --timeout=60s
	@echo "$(YELLOW)  Waiting for cert-manager to issue whoami-tls certificate...$(RESET)"
	@kubectl --context k3s-lima wait certificate whoami-tls -n apps \
		--for=condition=Ready --timeout=60s
	@echo "$(CYAN)  Testing HTTPS route: Host(whoami.local) → whoami pod via Traefik TLS...$(RESET)"
	@echo "  (retrying up to 30s for Traefik to register backend endpoints)"
	@SUCCESS=0; \
		for i in 1 2 3 4 5 6; do \
			STATUS=$$(curl -sk --resolve 'whoami.local:8443:127.0.0.1' \
				https://whoami.local:8443/ -w "%{http_code}" -o /tmp/lima-smoke-out.txt 2>&1); \
			if [ "$$STATUS" = "200" ]; then \
				echo "$(GREEN)✅ TLS smoke test passed — HTTP $$STATUS$(RESET)"; \
				cat /tmp/lima-smoke-out.txt | head -5; \
				SUCCESS=1; break; \
			fi; \
			echo "  Attempt $$i/6: HTTP $$STATUS — waiting 5s for Traefik..."; \
			sleep 5; \
		done; \
		if [ "$$SUCCESS" != "1" ]; then \
			echo "$(RED)❌ Smoke test failed after 30s — last HTTP $$STATUS$(RESET)"; \
			cat /tmp/lima-smoke-out.txt; \
			kubectl --context k3s-lima delete -f $(LIMA_TESTS_DIR)/smoke-test.yaml --ignore-not-found; \
			exit 1; \
		fi
	@echo "$(YELLOW)  Cleaning up smoke test resources...$(RESET)"
	@kubectl --context k3s-lima delete -f $(LIMA_TESTS_DIR)/smoke-test.yaml --ignore-not-found
	@echo "$(GREEN)✅ Lima TLS pipeline verified — mirrors production cert-manager → Traefik flow$(RESET)"

vm-k3s-smoke-monitoring: ## [Lima] Monitoring TLS smoke test: Grafana IngressRoute + cert-manager cert
	@echo "$(YELLOW)→ Running monitoring TLS smoke test on Lima k3s...$(RESET)"
	$(require_k3s_lima)
	@kubectl --context k3s-lima apply -f $(LIMA_TESTS_DIR)/smoke-monitoring.yaml
	@echo "$(YELLOW)  Waiting for grafana-smoke pod to be ready...$(RESET)"
	@kubectl --context k3s-lima rollout status deployment/grafana-smoke -n monitoring --timeout=120s
	@echo "$(YELLOW)  Waiting for cert-manager to issue grafana-smoke-tls certificate...$(RESET)"
	@kubectl --context k3s-lima wait certificate grafana-smoke-tls -n monitoring \
		--for=condition=Ready --timeout=60s
	@echo "$(CYAN)  Testing HTTPS route: Host(grafana.local) → Grafana via Traefik TLS...$(RESET)"
	@echo "  (retrying up to 30s for Traefik to register backend endpoints)"
	@SUCCESS=0; \
		for i in 1 2 3 4 5 6; do \
			STATUS=$$(curl -sk --resolve 'grafana.local:8443:127.0.0.1' \
				https://grafana.local:8443/api/health -w "%{http_code}" -o /tmp/lima-mon-smoke-out.txt 2>&1); \
			if [ "$$STATUS" = "200" ]; then \
				echo "$(GREEN)✅ Monitoring TLS smoke test passed — HTTP $$STATUS$(RESET)"; \
				cat /tmp/lima-mon-smoke-out.txt | head -3; \
				SUCCESS=1; break; \
			fi; \
			echo "  Attempt $$i/6: HTTP $$STATUS — waiting 5s for Traefik..."; \
			sleep 5; \
		done; \
		if [ "$$SUCCESS" != "1" ]; then \
			echo "$(RED)❌ Monitoring smoke test failed after 30s — last HTTP $$STATUS$(RESET)"; \
			cat /tmp/lima-mon-smoke-out.txt; \
			kubectl --context k3s-lima delete -f $(LIMA_TESTS_DIR)/smoke-monitoring.yaml --ignore-not-found; \
			exit 1; \
		fi
	@echo "$(YELLOW)  Cleaning up monitoring smoke test resources...$(RESET)"
	@kubectl --context k3s-lima delete -f $(LIMA_TESTS_DIR)/smoke-monitoring.yaml --ignore-not-found
	@echo "$(GREEN)✅ Lima monitoring TLS pipeline verified — mirrors production grafana-ingress.yaml flow$(RESET)"

vm-k3s-smoke-all: vm-k3s-smoke vm-k3s-smoke-monitoring ## [Lima] Run all smoke tests: whoami TLS + Grafana monitoring TLS
	@echo ""
	@echo "$(GREEN)🎉 All Lima smoke tests passed — whoami + Grafana pipelines verified$(RESET)"
