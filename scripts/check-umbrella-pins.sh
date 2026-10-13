#!/usr/bin/env bash
# =============================================================================
# check-umbrella-pins.sh — Verify that every platform-deployment dependency pin
# equals the version of the matching subchart in this repository.
#
# The whole repository shares one version: release-please bumps every
# charts/*/Chart.yaml and the umbrella's pins in the same release PR. This
# check is the watchdog for that invariant — a pin that lags (or leads) its
# subchart means a hand edit, or a chart added without being wired into
# .github/release/release-please-config.json.
#
# It reads the repository only, never the registry. Whether a pin can be
# resolved is established after publishing, by release-charts, which pushes the
# umbrella last and renders it. Asking the registry here would fail every
# release PR (the pins point at versions not published yet) and deadlock the
# publish behind CI.
#
# Detects only, never writes.
#
# Usage:
#   scripts/check-umbrella-pins.sh
#   scripts/check-umbrella-pins.sh --chart charts/platform-deployment
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

CHART_DIR="$REPO_ROOT/charts/platform-deployment"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) CHART_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

CHART_YAML="$CHART_DIR/Chart.yaml"
[ -f "$CHART_YAML" ] || { log_error "No Chart.yaml in $CHART_DIR"; exit 2; }

CHARTS_ROOT="$(cd "$CHART_DIR/.." && pwd)"

log_step "Checking dependency pins in $CHART_YAML"

deps="$(chart_oci_deps "$CHART_YAML")"
if [ -z "$deps" ]; then
  log_error "No oci:// dependency found in $CHART_YAML"
  log_error "An umbrella with no resolvable pin is not a pass — check the file."
  exit 1
fi

mismatched=0
checked=0

while IFS=$'\t' read -r name pinned _; do
  [ -n "$name" ] || continue
  checked=$((checked + 1))

  source_yaml="$CHARTS_ROOT/$name/Chart.yaml"
  if [ ! -f "$source_yaml" ]; then
    mismatched=$((mismatched + 1))
    log_error "$name — pinned $pinned but there is no $source_yaml"
    continue
  fi

  current="$(sed -nE 's/^version:[[:space:]]*"?([^"[:space:]#]+)"?.*/\1/p' "$source_yaml" | head -n 1)"
  if [ "$pinned" = "$current" ]; then
    log_ok "$name — $pinned"
  else
    mismatched=$((mismatched + 1))
    log_error "$name — pinned $pinned, repository is at $current"
  fi
done <<<"$deps"

echo ""
log_info "$checked dependency pin(s) checked against ${CHART_DIR##*/}"

if [ "$mismatched" -gt 0 ]; then
  log_error "$mismatched pin(s) differ from the subchart version in this repository."
  log_error "release-please bumps them together — check the extra-files in .github/release/release-please-config.json."
  exit 1
fi

log_ok "All $checked pin(s) match the repository"
