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
# Vault's self-signed TLS cert (CN=vault.<ns>.svc.cluster.local) is not trusted
# by the pod's system CA bundle, so every `vault` CLI call from inside the pod
# fails with x509 errors. Skip verification — safe since we only talk to
# localhost:8200 over the pod loopback. Override by exporting VAULT_SKIP_VERIFY=false.
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

# kubectl shorthand
K="${K:-kubectl --context "${KUBECONFIG_CONTEXT}"}"

# The token travels on stdin (first line), never as a process argument:
# argv is visible in local `ps`, in the kubectl exec API request, and in
# `ps` inside the pod — stdin is none of those.
# A tiny in-pod sh wrapper reads the token line, exports it, then execs vault;
# everything after that first line remains available as vault's own stdin.

# vault_exec <vault-args...>
# Run a vault CLI command inside the Vault pod (no stdin for vault itself).
vault_exec() {
  # shellcheck disable=SC2086
  printf '%s\n' "${VAULT_TOKEN}" | $K exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- \
    sh -c "IFS= read -r VAULT_TOKEN; export VAULT_TOKEN VAULT_SKIP_VERIFY=${VAULT_SKIP_VERIFY}; exec vault \"\$@\"" vault-cli "$@"
}

# vault_exec_stdin <vault-args...>
# Run a vault CLI command inside the Vault pod (with stdin for heredocs).
vault_exec_stdin() {
  # shellcheck disable=SC2086
  { printf '%s\n' "${VAULT_TOKEN}"; cat; } | $K exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- \
    sh -c "IFS= read -r VAULT_TOKEN; export VAULT_TOKEN VAULT_SKIP_VERIFY=${VAULT_SKIP_VERIFY}; exec vault \"\$@\"" vault-cli "$@"
}

# vault_kv_put <path> <key=value...>
# Write key-value pairs to Vault KV v2.
vault_kv_put() {
  local path="$1"; shift
  vault_exec kv put "$path" "$@"
}
