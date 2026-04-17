# shellcheck shell=bash
# lib/helm-repo.sh — Helm repo add + update helper.
#
# Usage:
#   _lib helm-repo.sh
#   helm_add_repo traefik https://helm.traefik.io/traefik
#   helm_add_repo grafana https://grafana.github.io/helm-charts
# ──────────────────────────────────────────────────────────────────────────────

helm_add_repo() {
  local name="$1" url="$2"
  helm repo add "${name}" "${url}" --force-update 2>/dev/null
  helm repo update "${name}"
}
