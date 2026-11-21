#!/bin/bash
set -euo pipefail

# =============================================================================
# argocd-deploy.sh — Install or upgrade ArgoCD from charts/platform-argocd
#
# Called by: task argocd:deploy. Run once after bootstrap; safe to re-run.
#
# The chart installed is this checkout's charts/platform-argocd, so the
# argo-cd version is the one pinned in its Chart.yaml (bumped with the rest of
# the repository), never a separate variable that can drift from it. Release
# `argocd` renders the same `argocd-*` resource names as the upstream chart
# installed under that release name, so an install made with `argo/argo-cd`
# upgrades in place.
#
# Required env (from .env):
#   KUBECONFIG_CONTEXT   kubectl context of the target cluster
#   ARGOCD_DOMAIN        e.g. argocd.example.com
# Usage: argocd-deploy.sh [values-file]
#
# Optional:
#   values-file / ARGOCD_VALUES_FILE   your per-cluster values, layered on the
#                        chart's defaults; path relative to the current
#                        directory. The argument wins; an empty one is ignored.
#   SERVER_IP            only used in the post-install DNS hint
#   HELM                 helm command (default: helm) — the test seam
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib require-vars.sh

require_vars KUBECONFIG_CONTEXT ARGOCD_DOMAIN

HELM="${HELM:-helm}"
CHART_DIR="${_RUN_REPO}/charts/platform-argocd"
ARGOCD_VALUES_FILE="${1:-${ARGOCD_VALUES_FILE:-}}"

if [[ -n "$ARGOCD_VALUES_FILE" && ! -f "$ARGOCD_VALUES_FILE" ]]; then
  log_error "ARGOCD_VALUES_FILE not found: ${ARGOCD_VALUES_FILE}"
  exit 1
fi

# The chart's own dependency (upstream argo-cd), at the exact version its
# Chart.yaml pins. `update`, not `build`: build needs the repository
# registered with `helm repo add` first and fails on a fresh machine (#122);
# update reads the repository URL from Chart.yaml.
"$HELM" dependency update "$CHART_DIR"

# Expanded as ${a[@]+"${a[@]}"} below: an empty array is "unbound" under
# `set -u` in bash 3.2, which is macOS's /bin/bash.
values_args=()
[[ -z "$ARGOCD_VALUES_FILE" ]] || values_args=(--values "$ARGOCD_VALUES_FILE")

"$HELM" upgrade --install argocd "$CHART_DIR" \
  --kube-context "$KUBECONFIG_CONTEXT" \
  --namespace argocd \
  --create-namespace \
  ${values_args[@]+"${values_args[@]}"} \
  --set "argo-cd.global.domain=${ARGOCD_DOMAIN}" \
  --set "argo-cd.configs.cm.url=https://${ARGOCD_DOMAIN}" \
  --wait \
  --timeout 300s

echo ""
echo "  UI:       https://${ARGOCD_DOMAIN}"
echo "  User:     admin"
echo "  Password: task argocd:password"
echo ""
echo "Next steps:"
echo "  1. Add DNS: ${ARGOCD_DOMAIN} → ${SERVER_IP:-<your ingress IP>}"
echo "  2. task argocd:add-repo ARGOCD_REPO_URL=git@github.com:<you>/<config-repo>.git GITHUB_DEPLOY_KEY=~/.ssh/deploy_key"
echo "  3. Apply your AppProjects and root Application (or ApplicationSets) from your config repo"
echo "  4. Add a GitHub webhook: https://${ARGOCD_DOMAIN}/api/webhook"
