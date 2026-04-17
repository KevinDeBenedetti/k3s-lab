# shellcheck shell=bash
# lib/k8s.sh — Reusable kubectl helpers for k3s-lab scripts.
#
# Usage:
#   _lib k8s.sh
#
# Prerequisites:
#   KUBECONFIG_CONTEXT  (used by kubectl if set)
# ──────────────────────────────────────────────────────────────────────────────

# wait_for_deployment NAMESPACE DEPLOYMENT [TIMEOUT]
# Wait for a deployment rollout to complete.
wait_for_deployment() {
  local namespace="$1" deployment="$2" timeout="${3:-120s}"
  kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="$timeout"
}

# namespace_exists NAME
# Return 0 if the namespace exists, 1 otherwise.
namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}
