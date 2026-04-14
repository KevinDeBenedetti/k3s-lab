#!/usr/bin/env bash
# =============================================================================
# common.sh — Reusable shell functions
#
# Source this file in scripts:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/lib/common.sh"
# =============================================================================

# Determine the repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source existing libraries
# shellcheck source=../../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../../lib/require-vars.sh
source "$REPO_ROOT/lib/require-vars.sh"

# ── Helm helpers ─────────────────────────────────────────────────────────────

# Add a Helm repo if not already added
helm_repo_ensure() {
  local name="$1" url="$2"
  if ! helm repo list 2>/dev/null | grep -q "^${name}"; then
    helm repo add "$name" "$url" --force-update
  fi
}

# ── Kubectl helpers ──────────────────────────────────────────────────────────

# Wait for a deployment to be ready
wait_for_deployment() {
  local namespace="$1" deployment="$2" timeout="${3:-120s}"
  kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="$timeout"
}

# Check if a namespace exists
namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}
