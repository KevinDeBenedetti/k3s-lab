#!/usr/bin/env bash
# =============================================================================
# check-umbrella-pins.sh — Report platform-deployment dependency pins that are
# behind the latest version published on the registry.
#
# Why this check exists: the umbrella's 7 pins are edited by hand, once per
# release. That is a deliberate choice — an alignment script existed and was
# removed on 2026-07-30, ~250 lines of shell to replace a single file edit. But
# the umbrella still sat on 0.13.0 for three consecutive releases, and nothing
# said so: the chart resolves fine, renders fine, and publishes fine while
# pointing at subcharts one or more releases old. What was missing was never the
# ability to make the edit, it was noticing it had been skipped.
#
# So this **detects only, and never writes**. It exits 1 on drift; bringing the
# pins forward stays a human gesture.
#
# Reads the registry through the OCI distribution API rather than GitHub's
# packages API — no token is needed for a public package, and it answers the
# question that actually matters: which versions can a consumer resolve today.
# (`gh api /user/packages/...` returned an empty list for a populated package on
# 2026-07-26 — see .github/workflows/cleanup-packages.yml.)
#
# Usage:
#   scripts/check-umbrella-pins.sh
#   scripts/check-umbrella-pins.sh --chart charts/platform-deployment
#
# Env:
#   GITHUB_TOKEN  optional — only needed if the packages are private.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/semver.sh
source "$REPO_ROOT/lib/semver.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"
# shellcheck source=../lib/registry.sh
source "$REPO_ROOT/lib/registry.sh"

CHART_DIR="$REPO_ROOT/charts/platform-deployment"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) CHART_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '3,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

command -v jq >/dev/null || { log_error "jq is required"; exit 2; }

CHART_YAML="$CHART_DIR/Chart.yaml"
[ -f "$CHART_YAML" ] || { log_error "No Chart.yaml in $CHART_DIR"; exit 2; }

log_step "Checking dependency pins in $CHART_YAML"

deps="$(chart_oci_deps "$CHART_YAML")"
if [ -z "$deps" ]; then
  log_error "No oci:// dependency found in $CHART_YAML"
  log_error "An umbrella with no resolvable pin is not a pass — check the file."
  exit 1
fi

behind=0
unresolved=0
checked=0

while IFS=$'\t' read -r name pinned repository; do
  [ -n "$name" ] || continue
  checked=$((checked + 1))

  IFS=$'\t' read -r host path < <(chart_oci_registry "$repository" "$name")

  tags=""
  if ! tags="$(registry_tags "$host" "$path" 2>/dev/null)" || [ -z "$tags" ]; then
    # Not knowing what is published is not the same as being up to date.
    unresolved=$((unresolved + 1))
    log_warn "$name — could not list tags at ${host}/${path}"
    continue
  fi

  latest="$(printf '%s\n' "$tags" | semver_latest)"
  if [ -z "$latest" ]; then
    unresolved=$((unresolved + 1))
    log_warn "$name — no release-shaped tag among: $(printf '%s' "$tags" | tr '\n' ' ')"
    continue
  fi

  case "$(semver_cmp "$pinned" "$latest")" in
    -1)
      behind=$((behind + 1))
      log_error "$name — pinned $pinned, published $latest"
      ;;
    1)
      # Pinned ahead of the registry: the pin cannot resolve at all. Worse than
      # lagging, and exactly the 0.13.x situation that froze ArgoCD.
      behind=$((behind + 1))
      log_error "$name — pinned $pinned but the registry only has up to $latest (unresolvable)"
      ;;
    *)
      log_ok "$name — $pinned"
      ;;
  esac
done <<<"$deps"

echo ""
log_info "$checked dependency pin(s) checked against ${CHART_DIR##*/}"

if [ "$behind" -gt 0 ]; then
  log_error "$behind pin(s) do not match the latest published version."
  log_error "Update them by hand in $CHART_YAML — this check never writes."
  exit 1
fi

if [ "$unresolved" -gt 0 ]; then
  log_error "$unresolved dependency/ies could not be resolved against the registry."
  log_error "Treated as a failure on purpose: an unanswered registry says nothing"
  log_error "about whether the pins are current."
  exit 1
fi

log_ok "All $checked pin(s) match the latest published version"
