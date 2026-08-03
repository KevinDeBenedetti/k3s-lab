#!/usr/bin/env bash
# =============================================================================
# bump-umbrella-pins.sh — Rewrite platform-deployment's dependency pins to a
# given, already-published version.
#
# History, because this file contradicts an older decision on purpose: an
# alignment script existed and was removed on 2026-07-30 — ~250 lines of shell
# to replace a single file edit, at a time when nothing consumed the umbrella.
# On 2026-08-03 the umbrella was promoted to the repository's public entry
# point ("try the whole platform in one command"), which turns the once-per-
# release manual bump into a gesture worth automating. This is the minimal
# write that decision requires: replace the `version:` of every dependency,
# touch nothing else, and verify the result through the same parser the checks
# use (lib/chart-deps.sh) so the writer and the watchdog cannot disagree.
#
# Called by release-charts.yml right after publishing: the target version has
# just been pushed to GHCR, so the "pins may only reference published
# versions" constraint holds by construction. check-umbrella-pins.sh remains
# the read-only watchdog; this script is only ever run with a version the
# registry already serves.
#
# Usage:
#   scripts/bump-umbrella-pins.sh --version 0.17.0
#   scripts/bump-umbrella-pins.sh --version 0.17.0 --chart charts/platform-deployment
#
# Exit codes: 0 pins now (or already) at the target — idempotent;
#             1 the rewrite failed verification; 2 usage error.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

CHART_DIR="$REPO_ROOT/charts/platform-deployment"
VERSION=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --chart)   CHART_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '3,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -n "$VERSION" ] || { log_error "--version is required"; exit 2; }
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) log_error "Not a release-shaped version: $VERSION"; exit 2 ;;
esac

CHART_YAML="$CHART_DIR/Chart.yaml"
[ -f "$CHART_YAML" ] || { log_error "No Chart.yaml in $CHART_DIR"; exit 2; }

deps="$(chart_deps "$CHART_YAML")"
if [ -z "$deps" ]; then
  log_error "No dependency found in $CHART_YAML — nothing to bump is a failure,"
  log_error "not a success: an umbrella without pins is not an umbrella."
  exit 1
fi

if ! printf '%s\n' "$deps" | awk -F'\t' -v v="$VERSION" '$2 != v { exit 1 }'; then
  log_step "Bumping dependency pins in $CHART_YAML to $VERSION"
else
  log_ok "All pins already at $VERSION — nothing to do"
  exit 0
fi

# The rewrite mirrors chart_deps' block detection exactly: only `version:`
# lines *inside* the dependencies block are touched. The chart's own top-level
# `version:` (and `appVersion:`) sit outside the block and keep their value —
# release-please owns those.
tmp="$(mktemp "${TMPDIR:-/tmp}/chart-yaml.XXXXXX")"
awk -v v="$VERSION" '
  /^dependencies:/        { deps = 1; print; next }
  deps && /^[^[:space:]]/ { deps = 0 }
  deps && $1 == "version:" { sub(/version:[[:space:]]*.*/, "version: " v) }
  { print }
' "$CHART_YAML" > "$tmp"

# Verify through the same parser the checks use before touching the real file:
# every dependency must now read exactly the target, and none may have gone
# missing in the rewrite.
before="$(printf '%s\n' "$deps" | wc -l | tr -d ' ')"
after_deps="$(chart_deps "$tmp")"
after="$(printf '%s\n' "$after_deps" | wc -l | tr -d ' ')"

if [ "$before" != "$after" ]; then
  log_error "Rewrite changed the dependency count ($before → $after) — aborting."
  rm -f "$tmp"
  exit 1
fi

if ! printf '%s\n' "$after_deps" | awk -F'\t' -v v="$VERSION" '$2 != v { exit 1 }'; then
  log_error "Rewrite left at least one pin off-target — aborting:"
  printf '%s\n' "$after_deps" | awk -F'\t' -v v="$VERSION" '$2 != v { print "    " $1 " — " $2 }' >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$CHART_YAML"

printf '%s\n' "$after_deps" | while IFS=$'\t' read -r name version _; do
  log_ok "$name — $version"
done
log_ok "$after pin(s) now at $VERSION"
