#!/usr/bin/env bash
# =============================================================================
# scripts/lib/common.sh — DEPRECATED: use lib/ helpers directly.
#
# Keeping this file as a compatibility shim. Source the canonical lib/ files
# instead (they work in both LOCAL and REMOTE execution modes via _lib):
#
#   _lib helm.sh   → helm_repo_ensure
#   _lib k8s.sh    → wait_for_deployment, namespace_exists
#
# This shim remains for any scripts that sourced it by path. It will be
# removed once all callers are updated.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../../lib/require-vars.sh
source "$REPO_ROOT/lib/require-vars.sh"
# shellcheck source=../../lib/helm.sh
source "$REPO_ROOT/lib/helm.sh"
# shellcheck source=../../lib/k8s.sh
source "$REPO_ROOT/lib/k8s.sh"
