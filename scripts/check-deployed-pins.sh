#!/usr/bin/env bash
# =============================================================================
# check-deployed-pins.sh — Report how far the ApplicationSet pins driving
# production have fallen behind what is published on the registry.
#
# The hole this fills, found on 2026-08-04: three watches existed and none
# asked this question.
#   check-traefik-advisories.sh  what the *repo* would deploy, vs advisories
#   check-deployed-charts.sh     what the *cluster* runs, vs advisories
#   check-umbrella-pins.sh       the umbrella's pins, vs the registry
# Nobody confronted infra's pins with the registry — which is how 0.9.1 stayed
# pinned for two weeks after being purged from GHCR, freezing the proxy on
# v3.7.1 (10 vulnerable ranges) while every other check reported green.
#
# Why this does not simply copy check-umbrella-pins.sh's verdict: the umbrella
# *must* reference the newest published version, so any drift there is a bug.
# Production pins are different — deliberately holding a version back is
# legitimate, and failing on every release would turn this red daily, which is
# how a signal stops being read. What is dangerous is not the gap, it is the
# *forgotten* gap. So drift is always reported in full, and only failed past
# --max-behind.
#
# Note also what this is NOT for: "the newer version fixes something the pinned
# one does not" is already answered, better, by check-deployed-charts.sh, which
# confronts the running versions with actual advisories. The value here is
# seeing it coming rather than confirming it.
#
# Usage:
#   scripts/check-deployed-pins.sh --applicationset <path>
#   scripts/check-deployed-pins.sh --applicationset <path> --max-behind 5
#   scripts/check-deployed-pins.sh --applicationset <path> --max-behind 0  # strictest:
#       any drift at all fails, like check-umbrella-pins.sh. Not the default,
#       and see the note above for why.
#
# Exit: 0 every pin within the threshold; 1 at least one past it, or a
#       repository could not be read; 2 usage error.
#
# Env:
#   GITHUB_TOKEN  optional — avoids the anonymous rate limit, required if the
#                 chart packages are private.
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

APPLICATIONSET=""
# Three releases. Rationale rather than taste: this repo cut 0.16.0 → 0.18.2 in
# under two days, so 1 would be red most mornings and unreadable within a week,
# while the incident this exists to catch sat *fourteen* releases behind. Three
# is comfortably above normal churn and far below any real drift.
MAX_BEHIND=3

while [ "$#" -gt 0 ]; do
  case "$1" in
    --applicationset) APPLICATIONSET="$2"; shift 2 ;;
    --max-behind)     MAX_BEHIND="$2"; shift 2 ;;
    -h|--help) sed -n '3,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -n "$APPLICATIONSET" ] || { log_error "--applicationset is required"; exit 2; }
[ -f "$APPLICATIONSET" ] || { log_error "No such ApplicationSet: $APPLICATIONSET"; exit 2; }
case "$MAX_BEHIND" in
  ''|*[!0-9]*) log_error "--max-behind must be a non-negative integer"; exit 2 ;;
esac
command -v jq >/dev/null || { log_error "jq is required"; exit 2; }

# ─── Where the charts come from, and which ones ─────────────────────────────
# Both read out of the ApplicationSet itself: it is the file ArgoCD acts on, so
# a second copy of either would drift exactly as the pins already have.
as_repo="$(applicationset_chart_repo "$APPLICATIONSET")"
if [ -z "$as_repo" ]; then
  log_error "No chart-bearing repoURL found in $APPLICATIONSET."
  log_error "Guessing a registry would check charts nobody deploys — failing."
  exit 1
fi
host="${as_repo%%/*}"
base="${as_repo#*/}"

charts="$(applicationset_charts "$APPLICATIONSET")"
if [ -z "$charts" ]; then
  log_error "No chart pinned in $APPLICATIONSET."
  log_error "Finding nothing to check is not the same as everything being current."
  exit 1
fi

log_step "Pins in ${APPLICATIONSET##*/} vs ${host}/${base} (fail past ${MAX_BEHIND} behind)"

stale=0
unreadable=0
checked=0

while IFS=$'\t' read -r chart pinned; do
  [ -n "$chart" ] || continue
  checked=$((checked + 1))
  path="${base}/${chart}"

  tags=""
  if ! tags="$(registry_tags "$host" "$path" 2>/dev/null)" || [ -z "$tags" ]; then
    # Not knowing what is published is not the same as being up to date.
    unreadable=$((unreadable + 1))
    log_warn "$chart — could not list tags at ${host}/${path}"
    continue
  fi

  latest="$(printf '%s\n' "$tags" | semver_latest)"
  if [ -z "$latest" ]; then
    unreadable=$((unreadable + 1))
    log_warn "$chart — no release-shaped tag among: $(printf '%s' "$tags" | tr '\n' ' ')"
    continue
  fi

  # Every published release strictly newer than the pin, oldest first. Counting
  # these rather than diffing version numbers is what makes "3 behind" mean
  # three actual releases: 0.17.0 → 0.18.2 is two, not eleven.
  newer="$(
    printf '%s\n' "$tags" | while IFS= read -r t; do
      [[ "$t" =~ ^[vV]?[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      [ "$(semver_cmp "$t" "$pinned")" = "1" ] && printf '%s\n' "$t"
    done | sort -t. -k1,1n -k2,2n -k3,3n
  )"
  behind="$(printf '%s' "$newer" | grep -c . || true)"

  if [ "$behind" -eq 0 ]; then
    # Pinned ahead of the registry cannot resolve at all — worse than lagging,
    # and exactly the 0.13.x situation that froze ArgoCD.
    if [ "$(semver_cmp "$pinned" "$latest")" = "1" ]; then
      log_error "$chart — pinned $pinned but the registry only has up to $latest (unresolvable)"
      stale=$((stale + 1))
    else
      log_ok "$chart — $pinned is the latest published"
    fi
    continue
  fi

  # Dates make the gap concrete: "2 behind" says little, "superseded 14 days
  # ago" is what tells you whether it was a decision or an oversight.
  first_newer="$(printf '%s\n' "$newer" | head -1)"
  since="$(registry_tag_created "$host" "$path" "$first_newer")"
  age=""
  if [ -n "$since" ]; then
    now_s="$(date -u +%s)"
    then_s="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$since" +%s 2>/dev/null ||
              date -u -d "$since" +%s 2>/dev/null || echo '')"
    [ -n "$then_s" ] && age=" ($(( (now_s - then_s) / 86400 ))d ago)"
  fi

  line="$chart — pinned $pinned, $behind behind (latest $latest)"
  detail="    superseded by $first_newer${age}; newer: $(printf '%s' "$newer" | tr '\n' ' ')"

  if [ "$behind" -gt "$MAX_BEHIND" ]; then
    stale=$((stale + 1))
    log_error "$line"
    log_error "$detail"
  else
    log_warn "$line"
    log_warn "$detail"
  fi
done <<<"$charts"

echo ""
log_info "$checked pin(s) checked against ${host}/${base}"

if [ "$stale" -gt 0 ]; then
  log_error "$stale pin(s) more than $MAX_BEHIND release(s) behind."
  log_error "Being behind is a choice; forgetting is not. Raise the pin in"
  log_error "$APPLICATIONSET, or confirm the lag is deliberate and raise"
  log_error "--max-behind. Check what a candidate really ships first:"
  log_error "    scripts/check-deployed-charts.sh --only <chart> --chart-version <candidate>"
  exit 1
fi

if [ "$unreadable" -gt 0 ]; then
  log_error "$unreadable repository/ies could not be read — treated as a failure:"
  log_error "an unanswered registry says nothing about whether the pins are current."
  exit 1
fi

log_ok "Every pin is within $MAX_BEHIND release(s) of the latest published"
