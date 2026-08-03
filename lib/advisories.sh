# shellcheck shell=bash
# lib/advisories.sh — Confront a component version with the security advisories
# published on its upstream GitHub repository.
#
# Generalized from lib/traefik-advisories.sh on 2026-08-03, when the deployed
# watch grew beyond Traefik: cert-manager and external-secrets ship from GitHub
# repos with the same advisory API, so the evaluator is shared for the same
# reason it was factored in the first place — several checks asking the same
# question of different versions must not be able to disagree about what
# "vulnerable" means.
#
# The **repository** endpoint is queried, not the global advisory database:
# only advisories carrying a CVE ID are mirrored globally, so `GET
# /advisories/<GHSA>` 404s on the CVE-less ones — including GHSA-3ccp, the one
# that caught us out. A 404 there proves nothing.
# See charts/platform-traefik/README.md, "Looking Traefik advisories up".
#
# Requires lib/log.sh and lib/semver.sh to be sourced first.
#
# Source this file, then use:
#   advisories_fetch <owner/repo> [FILE]   → the raw API payload
#   advisory_rows <payload>                → one TSV row per vulnerable range
#   advisory_scan <version> <rows>         → 0 clean, 1 vulnerable/unreadable

ADVISORIES_API_BASE="https://api.github.com"

# advisories_fetch OWNER/REPO [FILE] — the advisory payload, from FILE when
# given (offline runs and tests) or from the repository endpoint.
advisories_fetch() {
  local repo="$1" file="${2:-}" auth=()
  if [ -n "$file" ]; then
    cat "$file"
    return 0
  fi
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -sSf --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    "${auth[@]+"${auth[@]}"}" \
    "${ADVISORIES_API_BASE}/repos/${repo}/security-advisories?per_page=100"
}

# advisory_rows PAYLOAD — one TSV row per declared vulnerable range:
# ghsa, severity, published, range, patched, summary.
#
# One advisory declares a range per maintained release line (2.11.x, 3.6.x,
# 3.7.x…). All of them are emitted: the one containing our version is what
# matters, and nothing says in advance which that is.
advisory_rows() {
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

# _advisory_release_line VERSION — the major.minor a version belongs to.
_advisory_release_line() {
  local v="${1#[vV]}"
  v="${v%%-*}"; v="${v%%+*}"
  local -a f
  IFS=. read -r -a f <<<"$v"
  printf '%s.%s' "$((10#${f[0]//[^0-9]/}))" "$((10#${f[1]:-0}))" 2>/dev/null
}

# _advisory_patched_clears VERSION PATCHED — whether the advisory's own
# `patched_versions` field proves VERSION is fixed despite falling in the
# vulnerable range.
#
# Ranges are written by hand upstream and are routinely sloppier than the
# patched list — external-secrets GHSA-fq7h-9x26-6j22 declares `> 0.1.0` as
# vulnerable *forever* while stating `patched: 2.4.1`. The patched list is the
# operational truth, so an in-range version is cleared when:
#   - a patched version exists on its own release line and VERSION >= it, or
#   - VERSION is above *every* patched version (released after the fix).
# A same-line patched version *above* ours proves the opposite and never
# clears (cert-manager v1.20.2 against `patched: 1.19.6, 1.20.3` stays
# vulnerable: 1.20.3 is its line's fix and is not reached).
# An empty or unparsable patched list clears nothing — the range verdict
# stands.
_advisory_patched_clears() {
  local version="$1" patched="$2"
  local p any=0 above_all=1 vline pline

  vline="$(_advisory_release_line "$version")"

  while IFS= read -r p; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] || continue
    [[ "$p" =~ ^[vV]?[0-9]+(\.[0-9]+){1,2}$ ]] || return 1

    any=1
    pline="$(_advisory_release_line "$p")"
    if [ "$pline" = "$vline" ]; then
      # Our own line has a fix: reached or not decides, alone.
      [ "$(semver_cmp "$version" "$p")" != "-1" ] && return 0
      return 1
    fi
    [ "$(semver_cmp "$version" "$p")" = "1" ] || above_all=0
  done < <(printf '%s\n' "$patched" | tr ',' '\n')

  [ "$any" = 1 ] && [ "$above_all" = 1 ] && return 0
  return 1
}

# advisory_scan VERSION ROWS — confront VERSION with every range.
# Returns 0 when clean, 1 when covered by at least one range **or** when a range
# could not be evaluated. An unknown operator must never read as "not
# vulnerable", so an unparsable range fails the scan rather than being skipped.
advisory_scan() {
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
        if _advisory_patched_clears "$version" "$patched"; then
          log_info "$ghsa — $version falls in \"$range\" but the advisory's own"
          log_info "    patched list ($patched) covers it — treated as fixed"
          continue
        fi
        affected=$((affected + 1))
        log_error "$ghsa ($severity, $published) — $version falls in \"$range\""
        log_error "    patched in: $patched"
        log_error "    $summary"
        ;;
      2)
        # A prose range ("master branch") says nothing, but the advisory's own
        # patched list often still answers the question — external-secrets
        # GHSA-qwgc-rr35-h4x9 pairs an unreadable range with `patched:
        # v0.10.2`, which any later version demonstrably satisfies. Only when
        # neither field is readable does this stay a manual review.
        if _advisory_patched_clears "$version" "$patched"; then
          log_info "$ghsa — unparsable range \"$range\", but the advisory's own"
          log_info "    patched list ($patched) covers $version — treated as fixed"
          continue
        fi
        unreadable=$((unreadable + 1))
        log_warn "$ghsa — unparsable range \"$range\", check by hand"
        log_warn "    https://github.com/advisories/$ghsa"
        ;;
    esac
  done <<<"$rows"

  echo ""
  log_info "$checked range(s) evaluated"

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
