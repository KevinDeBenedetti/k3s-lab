# =============================================================================
# 45-security.mk — Security hardening targets
#
# Applies Pod Security Standards, NetworkPolicies, and PodDisruptionBudgets.
#
# Requires:
#   - kubectl configured with the target cluster context
#   - CNI supporting NetworkPolicy (kube-router, Calico, Cilium — NOT bare Flannel)
# =============================================================================

# ── Paths (allow override from consuming repo) ──────────────────────────────
# Default: platform/security/manifests (matches infra repo layout after v0.2.0)
SECURITY_DIR      ?= platform/security/manifests
NAMESPACES_FILE   ?= platform/security/manifests/namespaces.yaml

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: deploy-security security-status

deploy-security: ## Apply security hardening: PSS labels, NetworkPolicies, PDBs
	@echo "$(YELLOW)→ Applying Pod Security Standards namespace labels...$(RESET)"
	@kubectl apply -f $(NAMESPACES_FILE)
	@echo "$(YELLOW)→ Applying default-deny NetworkPolicies...$(RESET)"
	@kubectl apply -f $(SECURITY_DIR)/network-deny-policies.yaml
	@if [ -f "$(SECURITY_DIR)/network-allow-policies.yaml" ]; then \
		echo "$(YELLOW)→ Applying explicit allow NetworkPolicies...$(RESET)"; \
		kubectl apply -f $(SECURITY_DIR)/network-allow-policies.yaml; \
	fi
	@echo "$(GREEN)✅ Security hardening applied$(RESET)"

security-status: ## Show NetworkPolicies and PSS labels across all namespaces
	@echo "$(YELLOW)── NetworkPolicies ──$(RESET)"
	@kubectl get networkpolicies -A
	@echo ""
	@echo "$(YELLOW)── Pod Security Standards ──$(RESET)"
	@kubectl get namespaces -o custom-columns=\
'NAME:.metadata.name,ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce,AUDIT:.metadata.labels.pod-security\.kubernetes\.io/audit,WARN:.metadata.labels.pod-security\.kubernetes\.io/warn'
