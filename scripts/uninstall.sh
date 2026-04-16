#!/bin/bash
set -euo pipefail

# =============================================================================
# uninstall.sh — Tear down deployed workloads from a k3s cluster
#
# Removes Helm releases and namespaces. Configurable via environment variables.
#
# Optional:
#   KUBECONFIG_CONTEXT   Kubectl context (default: k3s-lab)
#   HELM_RELEASES        Space-separated "release namespace" pairs to uninstall
#   NAMESPACES           Space-separated list of namespaces to delete
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

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-lab}"
K="${K:-kubectl --context "${KUBECONFIG_CONTEXT}"}"

# Default Helm releases (override via HELM_RELEASES env var)
DEFAULT_HELM_RELEASES=(
  "argocd argocd"
  "kube-prometheus-stack monitoring"
  "loki monitoring"
  "promtail monitoring"
  "vault vault"
  "external-secrets external-secrets"
  "traefik ingress"
  "cert-manager cert-manager"
)

# Default namespaces to remove (override via NAMESPACES env var)
DEFAULT_NAMESPACES=(
  argocd monitoring vault external-secrets ingress cert-manager external-dns
)

log_error "⚠️  This will destroy all workloads on context: ${KUBECONFIG_CONTEXT}"
log_error "   Press Ctrl+C to abort, or wait 10 seconds..."
sleep 10

echo ""
log_warn "Removing Helm releases..."

if [[ -n "${HELM_RELEASES:-}" ]]; then
  IFS=$'\n' read -r -d '' -a _releases <<< "$HELM_RELEASES" || true
else
  _releases=("${DEFAULT_HELM_RELEASES[@]}")
fi

for release_ns in "${_releases[@]}"; do
  read -r r n <<< "$release_ns"
  echo "  → helm uninstall $r -n $n"
  helm uninstall "$r" -n "$n" --kube-context "${KUBECONFIG_CONTEXT}" 2>/dev/null || true
done

echo ""
log_warn "Removing namespaces..."

if [[ -n "${NAMESPACES:-}" ]]; then
  IFS=' ' read -r -a _namespaces <<< "$NAMESPACES"
else
  _namespaces=("${DEFAULT_NAMESPACES[@]}")
fi

for ns in "${_namespaces[@]}"; do
  # shellcheck disable=SC2086
  $K delete namespace "$ns" --ignore-not-found 2>/dev/null || true
done

echo ""
log_ok "Infrastructure removed"
log_warn "To fully decommission k3s, SSH into the server and run:"
echo "   /usr/local/bin/k3s-uninstall.sh"
