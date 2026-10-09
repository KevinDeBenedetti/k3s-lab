#!/usr/bin/env bash
# =============================================================================
# bump-umbrella-pins.sh — Rewrite some of platform-deployment's dependency pins
# to given, already-published versions.
#
# History, because this file contradicts an older decision on purpose: an
# alignment script existed and was removed on 2026-07-30 — ~250 lines of shell
# to replace a single file edit, at a time when nothing consumed the umbrella.
# On 2026-08-03 the umbrella was promoted to the repository's public entry
# point ("try the whole platform in one command"), which turns the once-per-
# release manual bump into a gesture worth automating. This is the minimal
# write that decision requires: replace the `version:` of the named
# dependencies, touch nothing else, and verify the result through the same
# parser the checks use (lib/chart-deps.sh) so the writer and the watchdog
# cannot disagree.
#
# Since 2026-10-08 every chart is versioned independently (one release-please
# component per chart), so there is no longer one version the whole umbrella
# moves to: each pin is set to its own subchart's version, `--set NAME=VERSION`
# once per dependency. A name the umbrella does not declare is ignored — the
# caller may pass every chart it knows about, including charts that are not
# subcharts (platform-base, platform-deployment itself).
#
# Called by release-charts.yml after publishing, with the latest version GHCR
# serves for each subchart: the "pins may only reference published versions"
# constraint holds by construction. check-umbrella-pins.sh remains the
# read-only watchdog.
#
# Usage:
#   scripts/bump-umbrella-pins.sh --set platform-traefik=0.24.0
#   scripts/bump-umbrella-pins.sh --set platform-argocd=0.23.1 --set platform-vault=0.25.0 \
#     --chart charts/platform-deployment
#
# Exit codes: 0 pins now (or already) at their targets — idempotent;
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
# "name<TAB>version" per requested pin.
TARGETS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --set)
      [ "$#" -ge 2 ] || { log_error "--set needs NAME=VERSION"; exit 2; }
      case "$2" in
        *=[0-9]*.[0-9]*.[0-9]*) ;;
        *) log_error "Not NAME=<release-shaped version>: $2"; exit 2 ;;
      esac
      TARGETS="${TARGETS}${2%%=*}"$'\t'"${2#*=}"$'\n'
      shift 2 ;;
    --chart)   CHART_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '3,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -n "$TARGETS" ] || { log_error "at least one --set NAME=VERSION is required"; exit 2; }

CHART_YAML="$CHART_DIR/Chart.yaml"
[ -f "$CHART_YAML" ] || { log_error "No Chart.yaml in $CHART_DIR"; exit 2; }

deps="$(chart_deps "$CHART_YAML")"
if [ -z "$deps" ]; then
  log_error "No dependency found in $CHART_YAML — nothing to bump is a failure,"
  log_error "not a success: an umbrella without pins is not an umbrella."
  exit 1
fi

# expected: every declared dependency with the version it must have afterwards
# (its target if one was given, its current pin otherwise).
expected="$(awk -F'\t' '
  NR == FNR { if ($1 != "") want[$1] = $2; next }
  { print $1 "\t" (($1 in want) ? want[$1] : $2) }
' <(printf '%s' "$TARGETS") <(printf '%s\n' "$deps"))"

current="$(printf '%s\n' "$deps" | cut -f1,2)"
if [ "$current" = "$expected" ]; then
  log_ok "All requested pins already at their target — nothing to do"
  exit 0
fi
log_step "Bumping dependency pins in $CHART_YAML"

# The rewrite mirrors chart_deps' block detection exactly: only `version:`
# lines *inside* the dependencies block are touched, and only for a dependency
# that has a target. The chart's own top-level `version:` (and `appVersion:`)
# sit outside the block and keep their value — release-please owns those.
tmp="$(mktemp "${TMPDIR:-/tmp}/chart-yaml.XXXXXX")"
awk -F'\t' '
  NR == FNR { if ($1 != "") want[$1] = $2; next }
  /^dependencies:/        { deps = 1; print; next }
  deps && /^[^[:space:]]/ { deps = 0 }
  deps {
    split($0, f, " ")
    if (f[1] == "-" && f[2] == "name:") name = f[3]
    else if (f[1] == "version:" && (name in want)) sub(/version:[[:space:]]*.*/, "version: " want[name])
  }
  { print }
' <(printf '%s' "$TARGETS") "$CHART_YAML" > "$tmp"

# Verify through the same parser the checks use before touching the real file:
# every dependency must read exactly what is expected, and none may have gone
# missing in the rewrite.
after="$(chart_deps "$tmp" | cut -f1,2)"
if [ "$after" != "$expected" ]; then
  log_error "Rewrite did not produce the expected pins — aborting:"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$after") >&2 || true
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$CHART_YAML"

printf '%s\n' "$after" | while IFS=$'\t' read -r name version; do
  log_ok "$name — $version"
done
log_ok "$(printf '%s\n' "$after" | wc -l | tr -d ' ') pin(s) checked after rewrite"
