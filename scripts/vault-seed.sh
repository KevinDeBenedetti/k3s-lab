#!/usr/bin/env bash
# =============================================================================
# scripts/vault-seed.sh — Seed core secrets into Vault from environment
#
# Called by: task vault:seed
#
# Reads environment variables set by task vault:seed (sourced from .env via
# Task's dotenv:) and seeds the following Vault KV v2 paths:
#   secret/argocd/oidc        — OIDC client credentials for ArgoCD
#   secret/grafana/admin      — Grafana admin username + password
#   secret/grafana/oauth      — Grafana Generic OAuth full config
#   secret/traefik/dashboard  — htpasswd users string for Traefik dashboard
#
# All values are read from environment — no interactive prompts.
# Missing optional values are skipped with a warning.
#
# Required env:
#   VAULT_ROOT_TOKEN, VAULT_POD, VAULT_NAMESPACE, KUBECONFIG_CONTEXT
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true

KUBECTL="${KUBECTL:-kubectl}"
K="${KUBECTL} --context ${KUBECONFIG_CONTEXT:-k3s-lab}"

# The token travels on stdin (first line), never as a process argument:
# argv is visible in local `ps`, in the kubectl exec API request, and inside
# the pod — stdin is none of those.
vault_exec() {
  # shellcheck disable=SC2086
  printf '%s\n' "${VAULT_ROOT_TOKEN}" | \
    ${K} exec -i -n "${VAULT_NAMESPACE:-vault}" "${VAULT_POD:-vault-0}" -- \
    sh -c 'IFS= read -r VAULT_TOKEN; export VAULT_TOKEN VAULT_SKIP_VERIFY=true; exec vault "$@"' vault-cli "$@"
}

echo "→ Seeding Vault secrets..."
echo ""

# ── secret/argocd/oidc ───────────────────────────────────────────────────────
if [[ -n "${OIDC_CLIENT_ID:-}" ]]; then
  vault_exec kv put secret/argocd/oidc \
    clientID="${OIDC_CLIENT_ID}" \
    clientSecret="${OIDC_CLIENT_SECRET:-}"
  echo "  ✓ argocd/oidc"
else
  echo "  (skipped argocd/oidc — OIDC_CLIENT_ID not set)"
fi

echo ""

# ── secret/grafana/admin ─────────────────────────────────────────────────────
if [[ -n "${GRAFANA_PASSWORD:-}" ]]; then
  vault_exec kv put secret/grafana/admin \
    username="admin" \
    password="${GRAFANA_PASSWORD}"
  echo "  ✓ grafana/admin"
else
  echo "  (skipped grafana/admin — GRAFANA_PASSWORD not set)"
fi

echo ""

# ── secret/grafana/oauth ─────────────────────────────────────────────────────
if [[ -n "${OIDC_CLIENT_ID:-}" && -n "${OIDC_AUTH_URL:-}" ]]; then
  vault_exec kv put secret/grafana/oauth \
    GF_AUTH_GENERIC_OAUTH_ENABLED="true" \
    GF_AUTH_GENERIC_OAUTH_NAME="${OIDC_PROVIDER_NAME:-OIDC}" \
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID="${OIDC_CLIENT_ID}" \
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="${OIDC_CLIENT_SECRET:-}" \
    GF_AUTH_GENERIC_OAUTH_SCOPES="openid email profile" \
    GF_AUTH_GENERIC_OAUTH_AUTH_URL="${OIDC_AUTH_URL}" \
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL="${OIDC_TOKEN_URL:-}" \
    GF_AUTH_GENERIC_OAUTH_API_URL="${OIDC_API_URL:-}" \
    GF_AUTH_GENERIC_OAUTH_USE_PKCE="true" \
    GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN="true" \
    GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN="true" \
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP="true" \
    GF_AUTH_DISABLE_LOGIN_FORM="true"
  echo "  ✓ grafana/oauth"
else
  echo "  (skipped grafana/oauth — OIDC_CLIENT_ID or OIDC_AUTH_URL not set)"
fi

echo ""

# ── secret/traefik/dashboard ─────────────────────────────────────────────────
if [[ -n "${DASHBOARD_PASSWORD:-}" ]]; then
  if ! command -v htpasswd >/dev/null 2>&1; then
    echo "  ❌ htpasswd not found — brew install httpd (skipping traefik/dashboard)"
  else
    # -i reads the password from stdin — keeps it out of `ps` (unlike -b)
    DASHBOARD_USERS="$(printf '%s\n' "${DASHBOARD_PASSWORD}" | htpasswd -ni "${DASHBOARD_USER:-admin}")"
    vault_exec kv put secret/traefik/dashboard \
      users="${DASHBOARD_USERS}"
    echo "  ✓ traefik/dashboard"
  fi
else
  echo "  (skipped traefik/dashboard — DASHBOARD_PASSWORD not set)"
fi

echo ""
echo "✅ Vault secrets seeded"
