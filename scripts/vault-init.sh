#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-init.sh — Initialize Vault, configure auth methods, create policies
#
# Run AFTER Vault pods are Running: make vault-init
#
# Steps:
#   1. Check init + seal status
#   2. Initialize (if needed) or unseal (if sealed)
#   3. Enable KV v2 secrets engine at 'secret/'
#   4. Enable + configure Kubernetes auth method
#   5. Create ESO read policy + Kubernetes role
#   6. Enable + configure OIDC auth method (if OIDC_CLIENT_ID is set)
#   7. Create vault-admin policy + OIDC role
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

if ! command -v python3 &> /dev/null; then
  echo "ERROR: python3 is required but not installed" >&2
  exit 1
fi

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-infra}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"

# ── Helpers: run vault CLI inside the Vault pod ───────────────────────────────
# vault_exec: for commands that do NOT need stdin (status, unseal, auth list…)
# vault_exec_stdin: for commands that read from stdin (policy write via heredoc)
vault_exec() {
  kubectl --context "${KUBECONFIG_CONTEXT}" exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN:-}" VAULT_SKIP_VERIFY=true vault "$@"
}
vault_exec_stdin() {
  kubectl --context "${KUBECONFIG_CONTEXT}" exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN:-}" VAULT_SKIP_VERIFY=true vault "$@"
}

# _json_field <json> <python-expression>
# Extract a value from JSON using a Python expression on variable 'd'.
_json_field() {
  echo "$1" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print($2)
" 2>/dev/null
}

# _parse_status <json> <field> <default>
# Extract a boolean field from Vault status JSON, returns "yes" or "no".
_parse_status() {
  _json_field "$1" "'yes' if d.get('$2') else 'no'" || echo "$3"
}

# ── Compute total steps (5 base + 2 if OIDC is configured) ───────────────────
if [[ -n "${OIDC_CLIENT_ID:-}" && -n "${OIDC_CLIENT_SECRET:-}" ]]; then
  TOTAL_STEPS=7
else
  TOTAL_STEPS=5
fi

# ── 0. Wait for Vault pod ────────────────────────────────────────────────────
log_info "Waiting for Vault pod to be Running..."
kubectl --context "${KUBECONFIG_CONTEXT}" wait pod/"${VAULT_POD}" \
  -n "${VAULT_NAMESPACE}" \
  --for=condition=Ready \
  --timeout=120s

# ── 1. Check init + seal status ──────────────────────────────────────────────
# vault status exits 0 (unsealed), 1 (error), or 2 (sealed) — all produce JSON.
STATUS_JSON=$(vault_exec status -format=json 2>/dev/null || true)

if [[ -z "${STATUS_JSON}" ]]; then
  log_error "Cannot reach Vault — is the pod running?"
  exit 1
fi

INITIALIZED=$(_parse_status "${STATUS_JSON}" initialized no)
SEALED=$(_parse_status "${STATUS_JSON}" sealed yes)

if [[ "${INITIALIZED}" == "yes" ]]; then
  log_info "Vault is already initialized — skipping init"

  if [[ "${SEALED}" == "yes" ]]; then
    log_step "[2/${TOTAL_STEPS}] Vault is sealed — unsealing..."
    if [[ -z "${VAULT_UNSEAL_KEY_1:-}" ]]; then
      read -r -s -p "  Unseal Key 1: " VAULT_UNSEAL_KEY_1 < /dev/tty; echo ""
    fi
    if [[ -z "${VAULT_UNSEAL_KEY_2:-}" ]]; then
      read -r -s -p "  Unseal Key 2: " VAULT_UNSEAL_KEY_2 < /dev/tty; echo ""
    fi
    vault_exec operator unseal "${VAULT_UNSEAL_KEY_1}"
    vault_exec operator unseal "${VAULT_UNSEAL_KEY_2}"
    log_info "Vault unsealed"
  else
    log_info "Vault is already unsealed"
  fi
else
  # ── Initialize ──────────────────────────────────────────────────────────
  log_step "[1/${TOTAL_STEPS}] Initializing Vault..."
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
for i, k in enumerate(d['unseal_keys_b64'], 1):
    print(f'Unseal Key {i}: {k}')
print()
print('Root Token:  ', d['root_token'])
"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""

  UNSEAL_KEY_1=$(_json_field "${INIT_OUTPUT}" "d['unseal_keys_b64'][0]")
  UNSEAL_KEY_2=$(_json_field "${INIT_OUTPUT}" "d['unseal_keys_b64'][1]")
  ROOT_TOKEN=$(_json_field "${INIT_OUTPUT}" "d['root_token']")

  # ── Unseal ──────────────────────────────────────────────────────────────
  log_step "[2/${TOTAL_STEPS}] Unsealing Vault..."
  vault_exec operator unseal "${UNSEAL_KEY_1}"
  vault_exec operator unseal "${UNSEAL_KEY_2}"
  log_info "Vault unsealed successfully"
fi

# ── Require root token for the rest ──────────────────────────────────────────
if [[ -z "${ROOT_TOKEN:-}" ]]; then
  if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
    ROOT_TOKEN="${VAULT_ROOT_TOKEN}"
  else
    echo ""
    read -r -s -p "Enter Vault root token: " ROOT_TOKEN < /dev/tty
    echo ""
  fi
fi

if [[ -z "${ROOT_TOKEN}" ]]; then
  log_error "No root token provided — cannot continue"
  exit 1
fi

VAULT_TOKEN="${ROOT_TOKEN}"

# Validate token before proceeding
if ! vault_exec token lookup > /dev/null 2>&1; then
  log_error "Invalid or expired root token — check your token and try again"
  echo "  Hint: set VAULT_ROOT_TOKEN in .env or pass it when prompted"
  exit 1
fi

# ── 3. Enable KV v2 ──────────────────────────────────────────────────────────
log_step "[3/${TOTAL_STEPS}] Enabling KV v2 secrets engine at 'secret/'..."
if vault_exec secrets list -format=json 2>/dev/null \
  | python3 -c "import sys,json; sys.exit(0 if 'secret/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
  log_info "KV v2 already enabled — skipping"
else
  vault_exec secrets enable -path=secret kv-v2
fi

# ── 4. Enable Kubernetes auth ────────────────────────────────────────────────
log_step "[4/${TOTAL_STEPS}] Configuring Kubernetes auth method..."
if vault_exec auth list -format=json 2>/dev/null \
  | python3 -c "import sys,json; sys.exit(0 if 'kubernetes/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
  log_info "Kubernetes auth already enabled — skipping"
else
  vault_exec auth enable kubernetes
fi

vault_exec write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# ── 5. Create policies and roles ─────────────────────────────────────────────
log_step "[5/${TOTAL_STEPS}] Creating policies and Kubernetes roles..."

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

# ── 6. Enable OIDC auth (optional — requires OIDC_CLIENT_ID) ────────────────
if [[ -n "${OIDC_CLIENT_ID:-}" && -n "${OIDC_CLIENT_SECRET:-}" ]]; then
  log_step "[6/${TOTAL_STEPS}] Configuring OIDC auth method..."

  VAULT_DOMAIN="${VAULT_DOMAIN:-}"
  ADMIN_EMAIL="${ADMIN_EMAIL:-}"

  if [[ -z "${VAULT_DOMAIN}" ]]; then
    log_warn "VAULT_DOMAIN not set — skipping OIDC (needed for callback URL)"
  else
    if vault_exec auth list -format=json 2>/dev/null \
      | python3 -c "import sys,json; sys.exit(0 if 'oidc/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
      log_info "OIDC auth already enabled — updating config"
    else
      vault_exec auth enable oidc
    fi

    vault_exec write auth/oidc/config \
      oidc_discovery_url="${OIDC_ISSUER_URL}" \
      oidc_client_id="${OIDC_CLIENT_ID}" \
      oidc_client_secret="${OIDC_CLIENT_SECRET}" \
      default_role="default"

    # ── 7. Create vault-admin policy + OIDC role ─────────────────────────────
    log_step "[7/${TOTAL_STEPS}] Creating vault-admin policy + OIDC role..."

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
  fi
else
  log_info "Skipping OIDC auth (OIDC_CLIENT_ID not set)"
fi

log_info "✅ Vault initialized and configured"
echo ""
echo "Next steps:"
echo "  make vault-seed                     # store secrets into Vault"
echo "  make deploy-eso                     # install External Secrets Operator"
echo "  make vault-apply-externalsecrets    # apply ClusterSecretStore + ExternalSecrets"
