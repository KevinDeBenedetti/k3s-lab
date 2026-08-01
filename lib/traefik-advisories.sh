# shellcheck shell=bash
# lib/traefik-advisories.sh — Confront a Traefik proxy version with the security
# advisories published on traefik/traefik.
#
# Factored out on 2026-08-01, when a second caller appeared. Two checks now ask
# the same question of two different versions, and they must not be able to
# disagree about what "vulnerable" means:
#   scripts/check-traefik-advisories.sh  — the version this repo would deploy
#   scripts/check-deployed-traefik.sh    — the version the cluster is running
#
# Those two diverged by a whole release once already: the repo sat on v3.7.9 and
# reported clean daily while production ran v3.7.8, covered by GHSA-3ccp, from
# 2026-07-27 to 2026-08-01. Sharing the evaluator is what keeps the second check
# honest rather than approximately right.
#
# Requires lib/log.sh and lib/semver.sh to be sourced first.
#
# Source this file, then use:
#   traefik_advisories_fetch [FILE]      → the raw API payload
#   traefik_advisory_rows <payload>      → one TSV row per vulnerable range
#   traefik_advisory_scan <version> <rows> → 0 clean, 1 vulnerable/unreadable

TRAEFIK_ADVISORIES_API="https://api.github.com/repos/traefik/traefik/security-advisories?per_page=100"

# traefik_advisories_fetch [FILE] — the advisory payload, from FILE when given
# (offline runs and tests) or from the repository endpoint.
#
# The repository endpoint, not the global advisory database: only advisories
# carrying a CVE ID are mirrored globally, so `GET /advisories/<GHSA>` 404s on
# the CVE-less ones — including GHSA-3ccp, the one that caught us out.
# See charts/platform-traefik/README.md, "Looking Traefik advisories up".
traefik_advisories_fetch() {
  local file="${1:-}" auth=()
  if [ -n "$file" ]; then
    cat "$file"
    return 0
  fi
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -sSf --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    "${auth[@]+"${auth[@]}"}" "$TRAEFIK_ADVISORIES_API"
}

# traefik_advisory_rows PAYLOAD — one TSV row per declared vulnerable range:
# ghsa, severity, published, range, patched, summary.
#
# One advisory declares a range per maintained release line (2.11.x, 3.6.x,
# 3.7.x…). All of them are emitted: the one containing our version is what
# matters, and nothing says in advance which that is.
traefik_advisory_rows() {
  printf '%s' "$1" | jq -r '
    .[]
    | . as $a
    | (($a.vulnerabilities // [])[]
       | select(.vulnerable_version_range != null)
       | [$a.ghsa_id, $a.severity, ($a.published_at // "")[0:10],
          .vulnerable_version_range, (.patched_versions // "?"),
          ($a.summary // "" | gsub("[\t\n]"; " "))]
       | @tsv)
  '
}

# traefik_advisory_scan VERSION ROWS — confront VERSION with every range.
# Returns 0 when clean, 1 when covered by at least one range **or** when a range
# could not be evaluated. An unknown operator must never read as "not
# vulnerable", so an unparsable range fails the scan rather than being skipped.
traefik_advisory_scan() {
  local version="$1" rows="$2"
  local affected=0 unreadable=0 checked=0
  local ghsa severity published range patched summary verdict

  if [ -z "$rows" ]; then
    log_error "No usable version range in the API response."
    log_error "Silence is not an absence of vulnerabilities — check the call."
    return 1
  fi

  while IFS=$'\t' read -r ghsa severity published range patched summary; do
    [ -n "$ghsa" ] || continue
    checked=$((checked + 1))

    set +e
    semver_in_range "$version" "$range"
    verdict=$?
    set -e

    case "$verdict" in
      0)
        affected=$((affected + 1))
        log_error "$ghsa ($severity, $published) — $version falls in \"$range\""
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
    log_error "$version is affected by $affected range(s)."
    return 1
  fi

  if [ "$unreadable" -gt 0 ]; then
    log_error "$unreadable range(s) could not be evaluated — manual review required."
    return 1
  fi

  log_ok "$version is not covered by any known vulnerable range"
  return 0
}
