#!/usr/bin/env bash
# =============================================================================
# check-deployed-traefik.sh — Confront the Traefik proxy version the cluster is
# actually running with the traefik/traefik advisories.
#
# Since 2026-08-03 this is a thin front over check-deployed-charts.sh, which
# asks the same question of every chart pinned in the ApplicationSet — the
# mechanics (pin → published chart → real content → advisories) turned out to
# be component-agnostic. This entry point stays because its interface is
# referenced from tracking issues, READMEs and infra comments, and because
# "check one Traefik candidate before pinning it" remains a real gesture:
#
#   scripts/check-deployed-traefik.sh --chart-version 0.16.0
#
# Usage (unchanged):
#   scripts/check-deployed-traefik.sh --applicationset <path>
#   scripts/check-deployed-traefik.sh --chart-version <v> [--file advisories.json]
#   scripts/check-deployed-traefik.sh --repo-path <owner/path/chart>
#
# Env:
#   GITHUB_TOKEN  optional — avoids the anonymous rate limit; required if the
#                 chart package is private.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

args=(--only platform-traefik)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --applicationset) args+=(--applicationset "$2"); shift 2 ;;
    --chart-version)  args+=(--chart-version "$2"); shift 2 ;;
    --file)           args+=(--file "$2"); shift 2 ;;
    # Historical flag: a full registry path like acme/charts/platform-traefik.
    # The walker takes the base; the chart segment is fixed by --only.
    --repo-path)      args+=(--repo-base "${2%/*}"); shift 2 ;;
    -h|--help) sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

exec "$SCRIPT_DIR/check-deployed-charts.sh" "${args[@]}"
