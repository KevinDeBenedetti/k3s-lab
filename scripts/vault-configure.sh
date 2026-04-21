#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-configure.sh — (Re)create Vault policies and Kubernetes roles
#
# Idempotent — safe to run multiple times.
# Run AFTER Vault is initialized and unsealed: make vault-configure
#
# Steps:
#   1. Create ESO read policy + Kubernetes role
#   2. Configure OIDC auth method (if OIDC_CLIENT_ID is set)
#   3. Create vault-admin policy + OIDC role
# =============================================================================

# shellcheck source=lib/script-init.sh
_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_src}" && "${_src}" != /dev/fd/* && -f "${_src}" ]]; then
  source "$(cd "$(dirname "${_src}")" && pwd)/../lib/script-init.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}/lib/script-init.sh")
fi
unset _src

_lib require-vars.sh

require_vars VAULT_ROOT_TOKEN

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-infra}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"

VAULT_TOKEN="${VAULT_ROOT_TOKEN}"

# ── Helpers ───────────────────────────────────────────────────────────────────
vault_exec() {
  kubectl --context "${KUBECONFIG_CONTEXT}" exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_SKIP_VERIFY=true vault "$@"
}
vault_exec_stdin() {
  kubectl --context "${KUBECONFIG_CONTEXT}" exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_SKIP_VERIFY=true vault "$@"
}

# ── 1. ESO read policy + Kubernetes role ──────────────────────────────────────
log_step "Creating ESO read policy + Kubernetes role..."

vault_exec_stdin policy write eso-read - <<'POLICY'
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
POLICY

vault_exec write auth/kubernetes/role/eso \
  bound_service_account_names="${ESO_SA}" \
  bound_service_account_namespaces="${ESO_NAMESPACE}" \
  policies="eso-read" \
  ttl=1h

log_info "ESO policy and role configured"

# ── 2. OIDC auth (optional) ──────────────────────────────────────────────────
if [[ -n "${OIDC_CLIENT_ID:-}" && -n "${OIDC_ISSUER_URL:-}" && -n "${VAULT_DOMAIN:-}" ]]; then
  log_step "Configuring OIDC auth method..."

  if vault_exec auth list -format=json 2>/dev/null \
    | python3 -c "import sys,json; sys.exit(0 if 'oidc/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
    log_info "OIDC auth already enabled — updating config"
  else
    vault_exec auth enable oidc
  fi

  vault_exec write auth/oidc/config \
    oidc_discovery_url="${OIDC_ISSUER_URL}" \
    oidc_client_id="${OIDC_CLIENT_ID}" \
    oidc_client_secret="${OIDC_CLIENT_SECRET:-}" \
    default_role="default"

  # ── 3. vault-admin policy + OIDC role ─────────────────────────────────────
  log_step "Creating vault-admin policy + OIDC role..."

  vault_exec_stdin policy write vault-admin - <<'POLICY'
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
path "sys/health" {
  capabilities = ["read", "sudo"]
}
path "sys/seal-status" {
  capabilities = ["read"]
}
path "sys/policies/*" {
  capabilities = ["read", "list"]
}
path "auth/*" {
  capabilities = ["read", "list"]
}
POLICY

  ADMIN_EMAIL="${ADMIN_EMAIL:-}"
  _oidc_policies="default,vault-admin"
  _bound_claims=()
  if [[ -n "${ADMIN_EMAIL}" ]]; then
    _bound_claims=("bound_claims={\"email\":\"${ADMIN_EMAIL}\"}")
  fi

  vault_exec write auth/oidc/role/default \
    user_claim="email" \
    allowed_redirect_uris="https://${VAULT_DOMAIN}/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    policies="${_oidc_policies}" \
    oidc_scopes="openid,email,profile" \
    ttl=12h \
    "${_bound_claims[@]}"

  log_info "OIDC configured — login at https://${VAULT_DOMAIN}"
else
  log_info "Skipping OIDC auth (OIDC_CLIENT_ID, OIDC_ISSUER_URL, or VAULT_DOMAIN not set)"
fi

log_info "✅ Vault configured"
