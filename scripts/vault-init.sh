#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-init.sh — Initialize Vault, configure Kubernetes auth, create policies
#
# Run AFTER Vault pods are Running: make vault-init
#
# What this does:
#   1. Initialize Vault (if not already initialized)
#   2. Unseal Vault with the generated unseal keys
#   3. Enable KV v2 secrets engine at 'secret/'
#   4. Enable Kubernetes auth method
#   5. Configure K8s auth (token reviewer binding)
#   6. Create read policies for each managed namespace
#   7. Create Kubernetes roles binding policies to ESO ServiceAccount
#
# Outputs:
#   - Unseal keys and root token printed to stdout ONLY
#   - ⚠️  Save these immediately — Vault never shows them again
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

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-infra}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="vault-0"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"

# ── Helper: run vault CLI inside the Vault pod ────────────────────────────────
vault_exec() {
  kubectl --context "${KUBECONFIG_CONTEXT}" exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- vault "$@"
}

# ── 0. Wait for Vault pod to be Running ───────────────────────────────────────
log_info "Waiting for Vault pod to be Running..."
kubectl --context "${KUBECONFIG_CONTEXT}" wait pod/"${VAULT_POD}" \
  -n "${VAULT_NAMESPACE}" \
  --for=condition=Ready \
  --timeout=120s

# ── 1. Check init status ──────────────────────────────────────────────────────
INIT_STATUS=$(vault_exec status -format=json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('initialized','false'))" 2>/dev/null || echo "false")

if [[ "${INIT_STATUS}" == "true" ]]; then
  log_info "Vault is already initialized — skipping init"
else
  # ── 2. Initialize ─────────────────────────────────────────────────────────
  log_step "[1/5] Initializing Vault..."
  INIT_OUTPUT=$(vault_exec operator init \
    -key-shares=3 \
    -key-threshold=2 \
    -format=json)

  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  ⚠️  VAULT INIT OUTPUT — SAVE THIS IMMEDIATELY"
  echo "  These keys and token will NEVER be shown again."
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('Unseal Key 1:', d['unseal_keys_b64'][0])
print('Unseal Key 2:', d['unseal_keys_b64'][1])
print('Unseal Key 3:', d['unseal_keys_b64'][2])
print()
print('Root Token:  ', d['root_token'])
"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""

  # Extract keys for use in this script
  UNSEAL_KEY_1=$(echo "${INIT_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][0])")
  UNSEAL_KEY_2=$(echo "${INIT_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][1])")
  ROOT_TOKEN=$(echo "${INIT_OUTPUT}"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['root_token'])")

  # ── 3. Unseal ────────────────────────────────────────────────────────────
  log_step "[2/5] Unsealing Vault..."
  vault_exec operator unseal "${UNSEAL_KEY_1}"
  vault_exec operator unseal "${UNSEAL_KEY_2}"

  log_info "Vault unsealed successfully"
fi

# ── 4. Require root token for the rest ───────────────────────────────────────
if [[ -z "${ROOT_TOKEN:-}" ]]; then
  if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
    ROOT_TOKEN="${VAULT_ROOT_TOKEN}"
  else
    echo ""
    read -r -s -p "Enter Vault root token: " ROOT_TOKEN
    echo ""
  fi
fi

export VAULT_TOKEN="${ROOT_TOKEN}"

# ── 5. Enable KV v2 ──────────────────────────────────────────────────────────
log_step "[3/5] Enabling KV v2 secrets engine at 'secret/'..."
vault_exec secrets list -format=json | python3 -c "import sys,json; print('secret/' in json.load(sys.stdin))" | grep -q True \
  && log_info "KV v2 already enabled — skipping" \
  || vault_exec secrets enable -path=secret kv-v2

# ── 6. Enable Kubernetes auth ─────────────────────────────────────────────────
log_step "[4/5] Configuring Kubernetes auth method..."
vault_exec auth list -format=json | python3 -c "import sys,json; print('kubernetes/' in json.load(sys.stdin))" | grep -q True \
  && log_info "Kubernetes auth already enabled — skipping" \
  || vault_exec auth enable kubernetes

# Configure K8s auth — use the cluster's internal API and Vault's own SA token
vault_exec write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# ── 7. Create policies and roles ─────────────────────────────────────────────
log_step "[5/5] Creating policies and Kubernetes roles..."

# Policy: ESO read-only access to all secrets
vault_exec policy write eso-read - <<'POLICY'
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
POLICY

# Kubernetes role for ESO — bound to the external-secrets ServiceAccount
vault_exec write auth/kubernetes/role/eso \
  bound_service_account_names="${ESO_SA}" \
  bound_service_account_namespaces="${ESO_NAMESPACE}" \
  policies="eso-read" \
  ttl=1h

log_info "✅ Vault initialized and configured"
echo ""
echo "Next steps:"
echo "  make vault-seed        # store all secrets into Vault"
echo "  make deploy-eso        # install External Secrets Operator"
echo "  kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml"
echo "  kubectl apply -f kubernetes/vault/external-secrets/"
