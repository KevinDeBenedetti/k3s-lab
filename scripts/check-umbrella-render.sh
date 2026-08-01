#!/usr/bin/env bash
# =============================================================================
# check-umbrella-render.sh — Verify that every subchart actually contributed to
# a rendered umbrella chart.
#
# Why this replaced a document count: `release-charts.yml` used to accept any
# render producing 7 or more documents, on the reasoning "one manifest per
# subchart". That is not what the number measures. Measured on 2026-08-01: an
# umbrella whose `platform-traefik` had been packaged *without* its own traefik
# subchart rendered **17** documents where a healthy one renders **401** — and
# sailed through, because 17 > 7. Four of the seven subcharts had contributed
# nothing at all, including the entire ingress. `helm dependency update` and
# `helm template` both exited 0 throughout: there was no other signal.
#
# So the question is not "how many manifests" but "which subcharts produced
# them". `helm template` answers it directly: every manifest carries a
# `# Source: <chart>/charts/<subchart>/...` comment. A subchart that contributed
# nothing has no such line, whatever the total.
#
# This is the check that would have caught the 0.13.0/0.13.1/0.13.2 incident,
# where three unrenderable charts were published without CI objecting.
#
# Assumes a render made with **default values**, where all dependencies are
# enabled — which is how release-charts renders it. A subchart deliberately
# disabled will be reported as missing, and the message names it, so the failure
# is readable rather than mysterious.
#
# Usage:
#   scripts/check-umbrella-render.sh --render /tmp/umbrella.yaml
#   scripts/check-umbrella-render.sh --chart charts/platform-deployment --render out.yaml
#   helm template x charts/platform-deployment | scripts/check-umbrella-render.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

CHART_DIR="$REPO_ROOT/charts/platform-deployment"
RENDER=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart)  CHART_DIR="$2"; shift 2 ;;
    --render) RENDER="$2"; shift 2 ;;
    -h|--help) sed -n '3,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

CHART_YAML="$CHART_DIR/Chart.yaml"
[ -f "$CHART_YAML" ] || { log_error "No Chart.yaml in $CHART_DIR"; exit 2; }

# Read the render from --render or stdin.
if [ -n "$RENDER" ]; then
  [ -f "$RENDER" ] || { log_error "No such render: $RENDER"; exit 2; }
  rendered="$(cat "$RENDER")"
else
  rendered="$(cat)"
fi

if [ -z "$rendered" ]; then
  log_error "Empty render — nothing to verify."
  log_error "An empty render must never count as a success."
  exit 1
fi

name="$(chart_name "$CHART_YAML")"
[ -n "$name" ] || { log_error "Could not read the chart name from $CHART_YAML"; exit 2; }

mapfile -t expected < <(chart_dep_names "$CHART_YAML")
if [ "${#expected[@]}" -eq 0 ]; then
  log_error "$CHART_YAML declares no dependency — nothing to attribute."
  log_error "An umbrella with no subchart is not a pass; check the file."
  exit 1
fi

# Which subcharts actually produced manifests, per helm's own attribution.
mapfile -t seen < <(
  printf '%s\n' "$rendered" |
    sed -n "s|^# Source: ${name}/charts/\([^/]*\)/.*|\1|p" |
    sort -u
)

total="$(printf '%s\n' "$rendered" | grep -c '^# Source:' || true)"

log_step "Render of $name: $total attributed manifest(s), ${#expected[@]} subchart(s) expected"

missing=0
for dep in "${expected[@]}"; do
  count="$(
    printf '%s\n' "$rendered" |
      grep -c "^# Source: ${name}/charts/${dep}/" || true
  )"
  if [ "$count" -gt 0 ]; then
    log_ok "$dep — $count manifest(s)"
  else
    log_error "$dep — contributed NOTHING"
    missing=$((missing + 1))
  fi
done

# Subcharts present in the render but not declared: not a failure, but worth
# surfacing — it means the packaged chart and its Chart.yaml disagree.
for s in ${seen[@]+"${seen[@]}"}; do
  found=0
  for dep in "${expected[@]}"; do
    [ "$s" = "$dep" ] && found=1 && break
  done
  [ "$found" -eq 0 ] && log_warn "$s rendered but is not declared in Chart.yaml"
done

echo ""

if [ "$missing" -gt 0 ]; then
  log_error "$missing of ${#expected[@]} subchart(s) produced no manifest."
  log_error "The umbrella is hollow: it packages the subchart but renders none of"
  log_error "its content — usually because that subchart's own dependencies were"
  log_error "not resolved before the umbrella was built. Publishing this would ship"
  log_error "a chart that installs cleanly and deploys nothing."
  exit 1
fi

log_ok "All ${#expected[@]} subchart(s) contributed — $total manifest(s) total"
