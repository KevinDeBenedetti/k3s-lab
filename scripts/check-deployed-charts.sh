#!/usr/bin/env bash
# =============================================================================
# check-deployed-charts.sh — Confront the component versions the **cluster is
# actually running** with their upstream security advisories.
#
# Grown out of check-deployed-traefik.sh on 2026-08-03: platform-cert-manager
# and platform-external-secrets are pinned in the same ApplicationSet, and
# nobody confronted their upstream versions with anything. The first run of
# this very extension found the deployed cert-manager v1.20.2 covered by
# GHSA-8rvj-mm4h-c258 (HIGH, patched in 1.20.3) — the mechanics generalize
# because the failure mode generalizes.
#
# The chain, per component:
#   ApplicationSet pin  →  published chart on GHCR  →  its effective component
#   version  →  the component's upstream advisories
#
# For Traefik the effective version is pin-aware (image.tag override, else the
# subchart's appVersion — lib/traefik-pin.sh). The other components carry no
# pin mechanism: the subchart's appVersion is the answer (lib/subchart.sh).
#
# Where to run it: the pins live in `infra`, this script lives in `k3s-lab`.
# From an infra checkout:
#
#   vendor/k3s-lab/scripts/check-deployed-charts.sh \
#     --applicationset argocd/applicationsets/platform.yaml
#
# Usage:
#   scripts/check-deployed-charts.sh --applicationset <path>
#   scripts/check-deployed-charts.sh --only platform-traefik --chart-version 0.16.0
#   scripts/check-deployed-charts.sh --only platform-traefik --chart-version 0.16.0 --file adv.json
#
# Env:
#   GITHUB_TOKEN  optional — avoids the 60 requests/h anonymous rate limit, and
#                 is required if the chart packages are private.
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
# shellcheck source=../lib/advisories.sh
source "$REPO_ROOT/lib/advisories.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

# Defaults for the pin-less modes (--only + --chart-version). When an
# ApplicationSet is given, the registry is read out of its own repoURL below —
# the file that names the versions also names where they resolve from, and a
# second copy of that truth drifts exactly like the version pins did.
REGISTRY="ghcr.io"
REPO_BASE="kevindebenedetti/charts"
REPO_BASE_SET=""
APPLICATIONSET=""
ONLY=""
CHART_VERSION=""
SOURCE_FILE=""

# component_spec CHART — "subchart<TAB>advisories-repo" for every chart this
# script knows how to interrogate. Adding a deployed chart means adding a line
# here — and nothing else, provided its wrapped component publishes advisories
# on its GitHub repository.
component_spec() {
  case "$1" in
    platform-traefik)          printf 'traefik\ttraefik/traefik\n' ;;
    platform-cert-manager)     printf 'cert-manager\tcert-manager/cert-manager\n' ;;
    platform-external-secrets) printf 'external-secrets\texternal-secrets/external-secrets\n' ;;
    *) return 1 ;;
  esac
}

COMPONENTS="platform-traefik platform-cert-manager platform-external-secrets"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --applicationset) APPLICATIONSET="$2"; shift 2 ;;
    --only)           ONLY="$2"; shift 2 ;;
    --chart-version)  CHART_VERSION="$2"; shift 2 ;;
    --file)           SOURCE_FILE="$2"; shift 2 ;;
    --repo-base)      REPO_BASE="$2"; REPO_BASE_SET=1; shift 2 ;;
    -h|--help) sed -n '3,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

command -v jq >/dev/null || { log_error "jq is required"; exit 2; }

if [ -n "$ONLY" ]; then
  component_spec "$ONLY" >/dev/null || {
    log_error "Unknown component: $ONLY (known: $COMPONENTS)"
    exit 2
  }
  COMPONENTS="$ONLY"
fi

if [ -n "$CHART_VERSION" ] && [ -z "$ONLY" ]; then
  log_error "--chart-version only makes sense with --only: a version applies to one chart."
  exit 2
fi

if [ -n "$SOURCE_FILE" ] && [ -z "$ONLY" ]; then
  log_error "--file only makes sense with --only: an advisory payload is per-component."
  exit 2
fi

if [ -z "$APPLICATIONSET" ] && [ -z "$CHART_VERSION" ]; then
  log_error "Nothing to check: pass --applicationset, or --only with --chart-version."
  exit 2
fi

if [ -n "$APPLICATIONSET" ] && [ ! -f "$APPLICATIONSET" ]; then
  log_error "No such ApplicationSet: $APPLICATIONSET"
  exit 2
fi

# The ApplicationSet names its own registry; an explicit --repo-base wins.
if [ -n "$APPLICATIONSET" ] && [ -z "$REPO_BASE_SET" ]; then
  as_repo="$(applicationset_chart_repo "$APPLICATIONSET")"
  if [ -z "$as_repo" ]; then
    log_error "No chart-bearing repoURL found in $APPLICATIONSET."
    log_error "Guessing a registry would check charts nobody deploys — failing."
    exit 1
  fi
  REGISTRY="${as_repo%%/*}"
  REPO_BASE="${as_repo#*/}"
  log_info "Registry from the ApplicationSet: ${REGISTRY}/${REPO_BASE}"
fi

# oci_chart_pull CHART VERSION DEST — pull the published chart out of the
# registry and print the extracted chart directory.
oci_chart_pull() {
  local chart="$1" version="$2" dest="$3"
  local repo_path="$REPO_BASE/$chart" auth=() token manifest digest

  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-u "x:${GITHUB_TOKEN}")
  token="$(
    curl -sSf --max-time 30 "${auth[@]+"${auth[@]}"}" \
      "https://${REGISTRY}/token?scope=repository:${repo_path}:pull&service=${REGISTRY}" |
      jq -r '.token // empty'
  )" || true

  if [ -z "$token" ]; then
    log_error "Could not obtain a pull token for ${REGISTRY}/${repo_path}."
    return 1
  fi

  manifest="$(
    curl -sSf --max-time 30 -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.oci.image.manifest.v1+json" \
      "https://${REGISTRY}/v2/${repo_path}/manifests/${version}"
  )" || {
    log_error "Chart ${repo_path}:${version} does not resolve on ${REGISTRY}."
    log_error "That is its own problem: ArgoCD cannot resolve it either."
    return 1
  }

  digest="$(printf '%s' "$manifest" | jq -r '
    .layers[]? | select(.mediaType | test("helm.chart.content")) | .digest' | head -1)"

  if [ -z "$digest" ]; then
    log_error "No helm chart layer in the manifest for ${chart}:${version}."
    return 1
  fi

  curl -sSfL --max-time 60 -H "Authorization: Bearer ${token}" \
    "https://${REGISTRY}/v2/${repo_path}/blobs/${digest}" -o "$dest/$chart.tgz"

  tar -xzf "$dest/$chart.tgz" -C "$dest"

  if [ ! -f "$dest/$chart/Chart.yaml" ]; then
    log_error "The published ${chart} artifact does not look like a chart (no Chart.yaml)."
    return 1
  fi

  printf '%s/%s\n' "$dest" "$chart"
}

work="$(mktemp -d "${TMPDIR:-/tmp}/deployed-charts.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failed=""

for chart in $COMPONENTS; do
  IFS=$'\t' read -r subchart adv_repo < <(component_spec "$chart")

  echo ""
  log_step "── $chart ──"

  # ─── Which chart version is deployed ────────────────────────────────────
  # Read from the ApplicationSet rather than asked for, so that the answer
  # comes from the file that actually drives ArgoCD instead of from a second
  # copy of the number that would drift exactly like the first one did.
  version="$CHART_VERSION"
  if [ -n "$APPLICATIONSET" ]; then
    version="$(applicationset_chart_version "$APPLICATIONSET" "$chart")"
    if [ -z "$version" ]; then
      log_error "No $chart version found in $APPLICATIONSET"
      log_error "Not finding the pin is not the same as there being none — failing."
      failed="$failed $chart"
      continue
    fi
  fi

  log_step "Deployed chart: $chart $version"

  # ─── Pull that published chart out of the registry ──────────────────────
  mkdir -p "$work/$chart"
  if ! chart_dir="$(oci_chart_pull "$chart" "$version" "$work/$chart")"; then
    failed="$failed $chart"
    continue
  fi

  # ─── What component version does that artifact actually deploy ──────────
  # Traefik is pin-aware (image.tag override, else the subchart's appVersion);
  # the others have no pin mechanism, so the subchart's appVersion is the
  # whole answer. Same resolution as the repo-side checks, so the watches
  # cannot disagree about what a chart deploys.
  if [ "$chart" = "platform-traefik" ]; then
    deployed="$(traefik_effective_tag "$chart_dir")"
  else
    deployed="$(subchart_appversion "$chart_dir" "$subchart")"
  fi

  if [ -z "$deployed" ]; then
    log_error "Could not determine the $subchart version inside $chart:$version."
    log_error "Not knowing the version is not the same as the version being safe — failing."
    failed="$failed $chart"
    continue
  fi

  log_step "Deployed $subchart: $deployed"

  # ─── Confrontation ──────────────────────────────────────────────────────
  if ! advisories="$(advisories_fetch "$adv_repo" "$SOURCE_FILE")"; then
    log_error "Could not fetch the $adv_repo advisories."
    log_error "An unanswered advisory API says nothing about safety — failing."
    failed="$failed $chart"
    continue
  fi
  rows="$(advisory_rows "$advisories")"

  if ! advisory_scan "$deployed" "$rows"; then
    failed="$failed $chart"
    continue
  fi

  log_ok "$chart $version runs a $subchart free of known advisories"
done

echo ""
if [ -n "$failed" ]; then
  log_error "Deployed component(s) covered by an advisory or unverifiable:${failed}."
  log_error ""
  log_error "This is what is RUNNING IN PRODUCTION, not the repository's state."
  log_error "Fix: bump the wrapped subchart in the corresponding charts/<name>/Chart.yaml"
  log_error "to a version shipping the patched component, release, then raise the pin in"
  log_error "the ApplicationSet to the new published chart. Check a candidate first:"
  log_error "    scripts/check-deployed-charts.sh --only <chart> --chart-version <candidate>"
  exit 1
fi

log_ok "Every deployed chart runs components free of known advisories"
