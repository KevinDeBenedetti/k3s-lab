#!/bin/bash
set -euo pipefail

# =============================================================================
# deploy-vault.sh — Deploy HashiCorp Vault + External Secrets Operator
#
# Run FROM YOUR LOCAL MACHINE with kubectl already configured.
# Usage: make deploy-vault  OR  make deploy-eso
#
# This script is split into two independently callable sections:
#   DEPLOY_VAULT=true   — install/upgrade Vault via Helm
#   DEPLOY_ESO=true     — install/upgrade External Secrets Operator via Helm
#
# Both default to true. Set to false to skip one.
# =============================================================================

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"

_run_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  source "$(cd "$(dirname "${_run_src}")" && pwd)/../lib/run-mode.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW}/lib/run-mode.sh")
fi

_lib log.sh
_lib load-env.sh

load_env "${_RUN_REPO:-.}/.env"

DEPLOY_VAULT="${DEPLOY_VAULT:-true}"
DEPLOY_ESO="${DEPLOY_ESO:-true}"

VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.29.1}"
ESO_CHART_VERSION="${ESO_CHART_VERSION:-0.14.3}"

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-infra}"

# ── 1. Vault ──────────────────────────────────────────────────────────────────
if [[ "${DEPLOY_VAULT}" == "true" ]]; then
  log_info "Deploying Vault ${VAULT_CHART_VERSION}..."

  [ -n "${VAULT_DOMAIN:-}" ] || { log_error "VAULT_DOMAIN is not set — add it to .env"; exit 1; }

  helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
  helm repo update hashicorp

  helm upgrade --install vault hashicorp/vault \
    --version "${VAULT_CHART_VERSION}" \
    --namespace vault \
    --create-namespace \
    --values "$(_k8s_file vault/vault-values.yaml)" \
    --wait \
    --timeout 120s

  log_info "Deploying Vault IngressRoute..."
  VAULT_DOMAIN="${VAULT_DOMAIN}" envsubst \
    < "$(_k8s_file vault/vault-ingressroute.yaml)" \
    | kubectl --context "${KUBECONFIG_CONTEXT}" apply -f -

  echo ""
  log_info "✅ Vault deployed"

  # Check actual state — vault may already be initialized from a previous deploy
  _status=$(kubectl --context "${KUBECONFIG_CONTEXT}" exec -n vault vault-0 \
    -- vault status -format=json 2>/dev/null || true)
  _init=$(echo "${_status}" | python3 -c "import sys,json; print('yes' if json.load(sys.stdin).get('initialized') else 'no')" 2>/dev/null || echo "no")
  _sealed=$(echo "${_status}" | python3 -c "import sys,json; print('yes' if json.load(sys.stdin).get('sealed') else 'no')" 2>/dev/null || echo "yes")

  if [[ "${_init}" == "no" ]]; then
    echo ""
    echo "  Vault is SEALED and UNINITIALIZED."
    echo "  Run: make vault-init"
  elif [[ "${_sealed}" == "yes" ]]; then
    echo ""
    echo "  Vault is initialized but SEALED."
    echo "  Run: make vault-unseal"
  else
    echo ""
    echo "  Vault is initialized and unsealed — ready to use."
  fi
fi

# ── 2. External Secrets Operator ──────────────────────────────────────────────
if [[ "${DEPLOY_ESO}" == "true" ]]; then
  log_info "Deploying External Secrets Operator ${ESO_CHART_VERSION}..."

  helm repo add external-secrets https://charts.external-secrets.io --force-update
  helm repo update external-secrets

  helm upgrade --install external-secrets external-secrets/external-secrets \
    --version "${ESO_CHART_VERSION}" \
    --namespace external-secrets \
    --create-namespace \
    --values "$(_k8s_file external-secrets/eso-values.yaml)" \
    --wait \
    --timeout 120s

  echo ""
  log_info "✅ External Secrets Operator deployed"
  echo ""
  echo "  Next: apply ClusterSecretStore + ExternalSecrets"
  echo "  kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml"
  echo "  kubectl apply -f kubernetes/vault/external-secrets/"
fi
