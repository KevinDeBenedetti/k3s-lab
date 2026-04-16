# shellcheck shell=bash
# lib/vault.sh — Reusable Vault helpers for k3s-lab scripts.
#
# Usage:
#   _lib vault.sh
#
# Prerequisites (set before sourcing):
#   KUBECONFIG_CONTEXT  (default: k3s-lab)
#   VAULT_NAMESPACE     (default: vault)
#   VAULT_POD           (default: vault-0)
#   VAULT_TOKEN or VAULT_ROOT_TOKEN
# ──────────────────────────────────────────────────────────────────────────────

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-lab}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"

# kubectl shorthand
K="${K:-kubectl --context "${KUBECONFIG_CONTEXT}"}"

# vault_exec <vault-args...>
# Run a vault CLI command inside the Vault pod (no stdin).
vault_exec() {
  # shellcheck disable=SC2086
  $K exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN}" vault "$@"
}

# vault_exec_stdin <vault-args...>
# Run a vault CLI command inside the Vault pod (with stdin for heredocs).
vault_exec_stdin() {
  # shellcheck disable=SC2086
  $K exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN}" vault "$@"
}

# vault_kv_put <path> <key=value...>
# Write key-value pairs to Vault KV v2.
vault_kv_put() {
  local path="$1"; shift
  vault_exec kv put "$path" "$@"
}
