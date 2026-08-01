#!/usr/bin/env bash
# =============================================================================
# check-deployed-traefik.sh — Confront the Traefik proxy version the **cluster
# is actually running** with the traefik/traefik advisories.
#
# Why this exists, and why it is not the same check as check-traefik-advisories:
# that one asks what *this repository* would deploy. This one asks what is
# deployed. The two are different questions and they have already given
# different answers for five days.
#
#   2026-07-27  GHSA-3ccp-42pg-hgv6 published, covering proxy <= v3.7.8
#   2026-07-27  repo already on v3.7.9 — the daily watch reports clean
#   …           infra still pinned platform-traefik 0.15.0's predecessor,
#               0.14.0, which pins v3.7.8 — production is vulnerable
#   2026-08-01  noticed by hand, pin bumped
#
# Nothing was broken in the repo, so nothing complained. The version that
# matters is the one in the artifact the cluster resolves, and that artifact is
# a *published* chart which can lag the source by any number of releases.
#
# The chain this walks:
#   ApplicationSet pin  →  published chart on GHCR  →  its effective proxy
#   version (image.tag, else the embedded subchart's appVersion)  →  advisories
#
# Where to run it: the pin lives in `infra`, this script lives in `k3s-lab`.
# `infra` vendors k3s-lab as a submodule, so from an infra checkout:
#
#   vendor/k3s-lab/scripts/check-deployed-traefik.sh \
#     --applicationset argocd/applicationsets/platform.yaml
#
# Usage:
#   scripts/check-deployed-traefik.sh --applicationset <path>
#   scripts/check-deployed-traefik.sh --chart-version 0.15.0
#   scripts/check-deployed-traefik.sh --chart-version 0.15.0 --file advisories.json
#
# Env:
#   GITHUB_TOKEN  optional — avoids the 60 requests/h anonymous rate limit, and
#                 is required if the chart package is private.
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
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

REGISTRY="ghcr.io"
REPO_PATH="kevindebenedetti/charts/platform-traefik"
APPLICATIONSET=""
CHART_VERSION=""
SOURCE_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --applicationset) APPLICATIONSET="$2"; shift 2 ;;
    --chart-version)  CHART_VERSION="$2"; shift 2 ;;
    --file)           SOURCE_FILE="$2"; shift 2 ;;
    --repo-path)      REPO_PATH="$2"; shift 2 ;;
    -h|--help) sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

command -v jq >/dev/null || { log_error "jq is required"; exit 2; }

# ─── Which chart version is deployed ────────────────────────────────────────
# Read from the ApplicationSet rather than asked for, so that the answer comes
# from the file that actually drives ArgoCD instead of from a second copy of the
# number that would drift exactly like the first one did.
if [ -n "$APPLICATIONSET" ]; then
  [ -f "$APPLICATIONSET" ] || { log_error "No such ApplicationSet: $APPLICATIONSET"; exit 2; }
  CHART_VERSION="$(applicationset_chart_version "$APPLICATIONSET" "${REPO_PATH##*/}")"
  if [ -z "$CHART_VERSION" ]; then
    log_error "No platform-traefik version found in $APPLICATIONSET"
    log_error "Not finding the pin is not the same as there being none — failing."
    exit 1
  fi
fi

if [ -z "$CHART_VERSION" ]; then
  log_error "Nothing to check: pass --applicationset or --chart-version."
  exit 2
fi

log_step "Deployed chart: ${REPO_PATH##*/} $CHART_VERSION"

# ─── Pull that published chart out of the registry ──────────────────────────
work="$(mktemp -d "${TMPDIR:-/tmp}/deployed-traefik.XXXXXX")"
trap 'rm -rf "$work"' EXIT

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-u "x:${GITHUB_TOKEN}")
token="$(
  curl -sSf --max-time 30 "${auth[@]+"${auth[@]}"}" \
    "https://${REGISTRY}/token?scope=repository:${REPO_PATH}:pull&service=${REGISTRY}" |
    jq -r '.token // empty'
)" || true

if [ -z "$token" ]; then
  log_error "Could not obtain a pull token for ${REGISTRY}/${REPO_PATH}."
  exit 1
fi

manifest="$(
  curl -sSf --max-time 30 -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://${REGISTRY}/v2/${REPO_PATH}/manifests/${CHART_VERSION}"
)" || {
  log_error "Chart ${REPO_PATH}:${CHART_VERSION} does not resolve on ${REGISTRY}."
  log_error "That is its own problem: ArgoCD cannot resolve it either."
  exit 1
}

digest="$(printf '%s' "$manifest" | jq -r '
  .layers[]? | select(.mediaType | test("helm.chart.content")) | .digest' | head -1)"

if [ -z "$digest" ]; then
  log_error "No helm chart layer in the manifest for ${CHART_VERSION}."
  exit 1
fi

curl -sSfL --max-time 60 -H "Authorization: Bearer ${token}" \
  "https://${REGISTRY}/v2/${REPO_PATH}/blobs/${digest}" -o "$work/chart.tgz"

tar -xzf "$work/chart.tgz" -C "$work"
chart_dir="$work/${REPO_PATH##*/}"

if [ ! -f "$chart_dir/Chart.yaml" ]; then
  log_error "The published artifact does not look like a chart (no Chart.yaml)."
  exit 1
fi

# ─── What proxy version does that artifact actually deploy ──────────────────
# Same resolution as everywhere else (pin, else the subchart's appVersion), so
# the two watches cannot disagree about what a chart deploys. The published
# chart embeds its subchart expanded rather than as a tarball; traefik-pin.sh
# handles both layouts.
deployed="$(traefik_effective_tag "$chart_dir")"

if [ -z "$deployed" ]; then
  log_error "Could not determine the proxy version inside ${REPO_PATH}:${CHART_VERSION}."
  log_error "Not knowing the version is not the same as the version being safe — failing."
  exit 1
fi

log_step "Deployed proxy: $deployed"

# ─── Confrontation ──────────────────────────────────────────────────────────
advisories="$(traefik_advisories_fetch "$SOURCE_FILE")"
rows="$(traefik_advisory_rows "$advisories")"

if ! traefik_advisory_scan "$deployed" "$rows"; then
  log_error ""
  log_error "This is the version RUNNING IN PRODUCTION, not the repository's."
  log_error "Fix: raise the platform-traefik pin in the ApplicationSet to a published"
  log_error "chart whose proxy is patched, and let ArgoCD reconcile. Check what a"
  log_error "candidate version really ships before pinning it:"
  log_error "    scripts/check-deployed-traefik.sh --chart-version <candidate>"
  exit 1
fi

log_ok "The deployed chart ${CHART_VERSION} runs a proxy free of known advisories"
