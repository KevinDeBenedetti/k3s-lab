#!/bin/bash
set -euo pipefail

# =============================================================================
# deploy-external-dns.sh — Deploy external-dns with Cloudflare provider
#
# Watches Kubernetes Ingress, Service and Traefik IngressRoute resources and
# automatically creates/updates DNS A records in Cloudflare.
#
# Run FROM YOUR LOCAL MACHINE with kubectl already configured.
# Usage: ./scripts/deploy-external-dns.sh
#
# Required vars (from .env or environment):
#   DOMAIN      — zone to manage (e.g. kevindb.dev)
#   SERVER_IP   — VPS public IP (for DNS A record value)
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"
_lib require-vars.sh
_lib helm-repo.sh

EXTERNAL_DNS_VERSION="${EXTERNAL_DNS_VERSION:-1.16.1}"
KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-$(kubectl config current-context 2>/dev/null)}"

require_vars DOMAIN SERVER_IP

log_info "Deploying external-dns ${EXTERNAL_DNS_VERSION} on cluster: $(kubectl config current-context)"

# --- 1. Namespace ---
log_step "[1/3] Namespace..."
kubectl --context "${KUBECONFIG_CONTEXT}" create namespace external-dns \
  --dry-run=client -o yaml | kubectl --context "${KUBECONFIG_CONTEXT}" apply -f -

# --- 2. Helm install ---
log_step "[2/3] external-dns ${EXTERNAL_DNS_VERSION} (Cloudflare)..."
helm_add_repo external-dns https://kubernetes-sigs.github.io/external-dns/

helm upgrade --install external-dns external-dns/external-dns \
  --version "${EXTERNAL_DNS_VERSION}" \
  --namespace external-dns \
  --values "$(_k8s_file external-dns/external-dns-values.yaml)" \
  --set "domainFilters[0]=${DOMAIN}" \
  --set "txtOwnerId=${KUBECONFIG_CONTEXT}" \
  ${EXTERNAL_DNS_EXTRA_ARGS:-} \
  --wait \
  --timeout 120s

log_info "Waiting for external-dns to be ready..."
kubectl --context "${KUBECONFIG_CONTEXT}" rollout status deployment/external-dns \
  -n external-dns --timeout=120s

# --- 3. Check token secret is present ---
log_step "[3/3] Checking Cloudflare token secret..."
if kubectl --context "${KUBECONFIG_CONTEXT}" get secret cloudflare-api-token-secret \
    -n external-dns >/dev/null 2>&1; then
  log_ok "cloudflare-api-token-secret found in external-dns namespace"
else
  log_warn "cloudflare-api-token-secret NOT found in external-dns namespace"
  echo ""
  echo "  Run: make vault-seed-cloudflare && make vault-apply-externalsecrets"
  echo "  This will sync the Cloudflare API token from Vault into Kubernetes."
fi

echo ""
log_ok "external-dns deployed!"
echo ""
echo "  Domain filter : ${DOMAIN}"
echo "  TXT owner ID  : ${KUBECONFIG_CONTEXT}"
echo "  Policy        : upsert-only (records are never auto-deleted)"
echo ""
echo "  To trigger DNS record creation, annotate your IngressRoute or Service:"
echo "    external-dns.alpha.kubernetes.io/hostname: app.${DOMAIN}"
echo ""
kubectl --context "${KUBECONFIG_CONTEXT}" get deployment external-dns -n external-dns
