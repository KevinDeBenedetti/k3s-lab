#!/usr/bin/env bash
# =============================================================================
# check-traefik-advisories.sh — Confront the Traefik proxy version deployed by
# charts/platform-traefik with the security advisories published on
# traefik/traefik.
#
# Why this watch exists: the deployed proxy version is a security decision that
# goes stale **silently**. GHSA-3ccp-42pg-hgv6 was published 12 days after we
# froze v3.7.8 — the pin became vulnerable without any signal being raised, not
# by CI, not by the upstream chart, and not by renovate (which tracks chart
# versions, not proxy versions). Dropping the pin on 2026-07-30 did not remove
# that risk, it moved it: we now inherit the subchart's appVersion, and an
# upstream chart that lags behind an advisory goes just as stale, just as
# quietly.
#
# The version checked is therefore the *effective* one (lib/traefik-pin.sh):
# `traefik.image.tag` when a pin is set, otherwise the subchart's appVersion.
#
# The repository endpoint is queried, not the global advisory database: only
# the advisories that carry a CVE ID are mirrored globally, so `GET
# /advisories/<GHSA>` 404s on the CVE-less ones — including GHSA-3ccp, the one
# that caught us out. A 404 there proves nothing. (And to go the other way, from
# a CVE, it is `GET /advisories?cve_id=<CVE>`: the path form expects a GHSA and
# 404s on a CVE, which reads misleadingly as "that CVE does not exist".)
# See charts/platform-traefik/README.md, "Looking Traefik advisories up".
#
# Exit 0 = that version is not covered by any vulnerable range.
# Exit 1 = it is vulnerable, or a range could not be evaluated.
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
# shellcheck source=../lib/traefik-advisories.sh
source "$REPO_ROOT/lib/traefik-advisories.sh"

CHART_DIR="$REPO_ROOT/charts/platform-traefik"
SOURCE_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file) SOURCE_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '3,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

command -v jq >/dev/null || { log_error "jq is required"; exit 2; }

# ─── Deployed version ───────────────────────────────────────────────────────
# With no pin the answer lives in the subchart's appVersion. This watch runs on
# a bare cron runner with no helm and no resolved dependency, so rather than
# pulling helm in just to learn one field, fetch the locked tarball straight
# from the dependency's repository. The version comes from Chart.lock, so what
# is inspected is the subchart this repo committed — not whatever upstream
# happens to serve as "latest" today.
deployed="$(traefik_effective_tag "$CHART_DIR")"

if [ -z "$deployed" ]; then
  locked_version="$(traefik_locked_field "$CHART_DIR" version)"
  locked_repo="$(traefik_locked_field "$CHART_DIR" repository)"

  if [ -z "$locked_version" ] || [ -z "$locked_repo" ]; then
    log_error "No traefik dependency in $CHART_DIR/Chart.lock — nothing to check."
    exit 1
  fi

  log_info "No pin and no local subchart — fetching traefik-$locked_version"
  deployed="$(
    curl -sSfL --max-time 60 "${locked_repo%/}/traefik/traefik-$locked_version.tgz" |
      tar -xzO traefik/Chart.yaml 2>/dev/null |
      awk '/^appVersion:[[:space:]]*/ { print $2; exit }'
  )" || true
fi

if [ -z "$deployed" ]; then
  log_error "Could not determine the Traefik proxy version deployed by $CHART_DIR."
  log_error "Not knowing the version is not the same as the version being safe — failing."
  exit 1
fi

log_step "Deployed proxy: $deployed"

# ─── Advisories ─────────────────────────────────────────────────────────────
advisories="$(traefik_advisories_fetch "$SOURCE_FILE")"
rows="$(traefik_advisory_rows "$advisories")"

if ! traefik_advisory_scan "$deployed" "$rows"; then
  log_error "Fix: bump the traefik subchart if a newer one already ships the patched"
  log_error "proxy, otherwise re-add the traefik.image.tag pin (never versionOverride)."
  log_error "Reminder: update the comment in $CHART_DIR/values.yaml and the advisory"
  log_error "table in $CHART_DIR/README.md."
  exit 1
fi
