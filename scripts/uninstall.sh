#!/bin/bash
set -euo pipefail

# =============================================================================
# uninstall.sh — Tear down deployed workloads from a k3s cluster
#
# Called by: task deploy:uninstall (which asks for confirmation first).
#
# Uninstalls every Helm release found in the target namespaces, whatever its
# name (the docs install the same charts under several release names), then
# deletes the namespaces. Anything that could not be removed is named, and the
# script exits non-zero; something already gone is not an error.
#
# Optional:
#   KUBECONFIG_CONTEXT       kubectl context (default: k3s-lab)
#   NAMESPACES               space-separated namespaces to empty and delete
#                            (default: every namespace the platform charts use)
#   HELM_RELEASES            newline-separated "release namespace" pairs to
#                            uninstall instead of discovering them
#   UNINSTALL_GRACE_SECONDS  seconds to wait before starting, to abort with
#                            Ctrl+C (default: 10)
#   K, HELM                  kubectl / helm commands — the test seams
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-lab}"
K="${K:-kubectl --context "${KUBECONFIG_CONTEXT}"}"
HELM="${HELM:-helm}"

# The namespaces of charts/platform-base (values.yaml `namespaces:`), plus the
# ones the other platform charts are installed into by convention: argocd,
# security (platform-security) and platform (the umbrella chart).
DEFAULT_NAMESPACES=(
  argocd platform security
  apps ingress cert-manager monitoring vault external-dns external-secrets auth
)

if [[ -n "${NAMESPACES:-}" ]]; then
  IFS=' ' read -r -a namespaces <<<"$NAMESPACES"
else
  namespaces=("${DEFAULT_NAMESPACES[@]}")
fi

# shellcheck disable=SC2086
if ! $K cluster-info --request-timeout=10s >/dev/null 2>&1; then
  log_error "Cannot reach the cluster on context ${KUBECONFIG_CONTEXT} — nothing was removed"
  exit 1
fi

log_error "⚠️  This will destroy all workloads on context: ${KUBECONFIG_CONTEXT}"
log_error "   Press Ctrl+C to abort, or wait ${UNINSTALL_GRACE_SECONDS:-10} seconds..."
sleep "${UNINSTALL_GRACE_SECONDS:-10}"

failures=()

# ── Helm releases ────────────────────────────────────────────────────────────
releases=()
if [[ -n "${HELM_RELEASES:-}" ]]; then
  IFS=$'\n' read -r -d '' -a releases <<<"$HELM_RELEASES" || true
else
  for ns in "${namespaces[@]}"; do
    while IFS= read -r r; do
      [[ -z "$r" ]] || releases+=("$r $ns")
    done < <("$HELM" list -n "$ns" -q --kube-context "${KUBECONFIG_CONTEXT}" 2>/dev/null || true)
  done
fi

echo ""
log_warn "Removing Helm releases..."
for release_ns in ${releases[@]+"${releases[@]}"}; do
  read -r r n <<<"$release_ns"
  echo "  → helm uninstall $r -n $n"
  if ! err="$("$HELM" uninstall "$r" -n "$n" --kube-context "${KUBECONFIG_CONTEXT}" 2>&1 >/dev/null)"; then
    if [[ "$err" == *"not found"* ]]; then
      echo "    (not installed)"
    else
      log_error "    helm uninstall $r -n $n failed: ${err}"
      failures+=("release $r ($n)")
    fi
  fi
done

# ── Namespaces ───────────────────────────────────────────────────────────────
echo ""
log_warn "Removing namespaces..."
for ns in "${namespaces[@]}"; do
  # shellcheck disable=SC2086
  if ! err="$($K delete namespace "$ns" --ignore-not-found 2>&1 >/dev/null)"; then
    log_error "  namespace $ns could not be deleted: ${err}"
    failures+=("namespace $ns")
  fi
done

echo ""
if [[ ${#failures[@]} -gt 0 ]]; then
  log_error "Not everything was removed (${#failures[@]}):"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi

log_ok "Infrastructure removed"
log_warn "To fully decommission k3s, SSH into the server and run:"
echo "   /usr/local/bin/k3s-uninstall.sh"
