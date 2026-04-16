#!/bin/bash
set -euo pipefail

# =============================================================================
# deploy-grafana-oauth.sh — Restart Grafana to pick up OAuth secret from Vault
#
# Checks for grafana-oauth-secret in the monitoring namespace and triggers
# a rolling restart so Grafana picks up the updated credentials.
#
# Required:
#   GRAFANA_DOMAIN          Used to verify config (from cluster.env)
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

require_vars GRAFANA_DOMAIN

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-lab}"
K="${K:-kubectl --context ${KUBECONFIG_CONTEXT}}"

GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-monitoring}"
GRAFANA_SECRET="${GRAFANA_SECRET:-grafana-oauth-secret}"
GRAFANA_DEPLOYMENT="${GRAFANA_DEPLOYMENT:-kube-prometheus-stack-grafana}"

if ! $K get secret "$GRAFANA_SECRET" -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
  log_warn "Skipping Grafana OAuth — ${GRAFANA_SECRET} not found in ${GRAFANA_NAMESPACE}"
  exit 0
fi

log_warn "Restarting Grafana for OAuth2..."
$K rollout restart deployment/"$GRAFANA_DEPLOYMENT" -n "$GRAFANA_NAMESPACE"
$K rollout status deployment/"$GRAFANA_DEPLOYMENT" -n "$GRAFANA_NAMESPACE" --timeout=120s

log_ok "Grafana OAuth2 enabled (${GRAFANA_DOMAIN})"
