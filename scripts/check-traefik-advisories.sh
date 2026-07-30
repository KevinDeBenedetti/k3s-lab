#!/usr/bin/env bash
# =============================================================================
# check-traefik-advisories.sh — Confront the traefik.image.tag pin with the
# security advisories published on traefik/traefik.
#
# Why this watch exists: the pin is a security decision that goes stale
# **silently**. GHSA-3ccp-42pg-hgv6 was published 12 days after we froze v3.7.8
# — the pin became vulnerable without any signal being raised, not by CI, not by
# the upstream chart, and not by renovate (which tracks chart versions, not
# proxy versions).
#
# Traefik advisories are not in GitHub's global database
# (`GET /advisories/<GHSA>` returns 404): the repository must be queried.
#
# Exit 0 = the pin is not covered by any vulnerable range.
# Exit 1 = the pin is vulnerable, or a range could not be evaluated.
#
# Usage:
#   scripts/check-traefik-advisories.sh
#   scripts/check-traefik-advisories.sh --file advisories.json   # offline
#
# Env:
#   GITHUB_TOKEN  optional — avoids the 60 requests/h anonymous rate limit.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/semver.sh
source "$REPO_ROOT/lib/semver.sh"
# shellcheck source=../lib/traefik-pin.sh
source "$REPO_ROOT/lib/traefik-pin.sh"

API="https://api.github.com/repos/traefik/traefik/security-advisories?per_page=100"
VALUES="$REPO_ROOT/charts/platform-traefik/values.yaml"
SOURCE_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file) SOURCE_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

command -v jq >/dev/null || { log_error "jq is required"; exit 2; }

# ─── Pinned version ─────────────────────────────────────────────────────────
pinned="$(traefik_pinned_tag "$VALUES")"
if [ -z "$pinned" ]; then
  log_error "No traefik.image.tag in $VALUES — nothing to confront with the advisories."
  exit 1
fi

log_step "Pinned proxy: $pinned"

# ─── Advisories ─────────────────────────────────────────────────────────────
if [ -n "$SOURCE_FILE" ]; then
  advisories="$(cat "$SOURCE_FILE")"
else
  auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  advisories="$(curl -sSf --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    "${auth[@]+"${auth[@]}"}" "$API")"
fi

# One advisory declares a range per maintained release line (2.11.x, 3.6.x,
# 3.7.x…). All of them must be checked: the one containing our pin is what
# matters, and nothing tells us in advance which one that is.
rows="$(printf '%s' "$advisories" | jq -r '
  .[]
  | . as $a
  | (($a.vulnerabilities // [])[]
     | select(.vulnerable_version_range != null)
     | [$a.ghsa_id, $a.severity, ($a.published_at // "")[0:10],
        .vulnerable_version_range, (.patched_versions // "?"),
        ($a.summary // "" | gsub("[\t\n]"; " "))]
     | @tsv)
')"

if [ -z "$rows" ]; then
  log_error "No usable version range in the API response."
  log_error "Silence is not an absence of vulnerabilities — check the call."
  exit 1
fi

# ─── Confrontation ──────────────────────────────────────────────────────────
affected=0
unreadable=0
checked=0

while IFS=$'\t' read -r ghsa severity published range patched summary; do
  [ -n "$ghsa" ] || continue
  checked=$((checked + 1))

  set +e
  semver_in_range "$pinned" "$range"
  verdict=$?
  set -e

  case "$verdict" in
    0)
      affected=$((affected + 1))
      log_error "$ghsa ($severity, $published) — $pinned falls in \"$range\""
      log_error "    patched in: $patched"
      log_error "    $summary"
      ;;
    2)
      unreadable=$((unreadable + 1))
      log_warn "$ghsa — unparsable range \"$range\", check by hand"
      log_warn "    https://github.com/traefik/traefik/security/advisories/$ghsa"
      ;;
  esac
done <<<"$rows"

echo ""
log_info "$checked range(s) evaluated across the traefik/traefik advisories"

if [ "$affected" -gt 0 ]; then
  log_error "$pinned is affected by $affected range(s) — raise traefik.image.tag."
  log_error "Reminder: update the comment in $VALUES and the table in the README."
  exit 1
fi

if [ "$unreadable" -gt 0 ]; then
  log_error "$unreadable range(s) could not be evaluated — manual review required."
  exit 1
fi

log_ok "$pinned is not covered by any known vulnerable range"
