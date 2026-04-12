#!/bin/bash
set -euo pipefail

# =============================================================================
# deploy-oauth2-proxy.sh — Deploy oauth2-proxy as OIDC ForwardAuth gateway
#
# Installs oauth2-proxy in the auth namespace using Helm.
# Expects OIDC credentials via --set flags or ExternalSecret.
#
# Required env vars:
#   OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OAUTH2_COOKIE_SECRET
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"
_lib require-vars.sh
_lib helm-repo.sh

# --- Pinned version (can be overridden via .env) ---
OAUTH2_PROXY_CHART_VERSION="${OAUTH2_PROXY_CHART_VERSION:-}"

# --- Validate ---
require_vars DOMAIN

log_info "Deploying oauth2-proxy to namespace: auth"

# --- 1. Helm repo ---
log_step "[1/2] Adding oauth2-proxy Helm repo..."
helm_add_repo oauth2-proxy https://oauth2-proxy.github.io/manifests

# --- 2. Install / upgrade ---
log_step "[2/2] Installing oauth2-proxy..."

HELM_ARGS=(
  upgrade --install oauth2-proxy oauth2-proxy/oauth2-proxy
  -n auth --create-namespace
  -f "$(_k8s_file auth/oauth2-proxy-values.yaml)"
)

# Add version pin if set
if [ -n "${OAUTH2_PROXY_CHART_VERSION}" ]; then
  HELM_ARGS+=(--version "${OAUTH2_PROXY_CHART_VERSION}")
fi

# Inject secrets if provided as env vars (otherwise expect ExternalSecret)
if [ -n "${OIDC_CLIENT_ID:-}" ]; then
  HELM_ARGS+=(
    --set "config.clientID=${OIDC_CLIENT_ID}"
    --set "config.clientSecret=${OIDC_CLIENT_SECRET:-}"
    --set "config.cookieSecret=${OAUTH2_COOKIE_SECRET:-}"
  )
  log_info "Using OIDC credentials from environment"
else
  log_info "No OIDC_CLIENT_ID set — expecting credentials via ExternalSecret"
fi

helm "${HELM_ARGS[@]}"

log_ok "oauth2-proxy deployed — verify: kubectl get pods -n auth"
