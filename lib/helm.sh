# shellcheck shell=bash
# lib/helm.sh — Reusable Helm helpers for k3s-lab scripts.
#
# Usage:
#   _lib helm.sh
# ──────────────────────────────────────────────────────────────────────────────

# helm_repo_ensure NAME URL
# Add a Helm repo if not already registered.
helm_repo_ensure() {
  local name="$1" url="$2"
  if ! helm repo list 2>/dev/null | grep -q "^${name}"; then
    helm repo add "$name" "$url" --force-update
  fi
}
