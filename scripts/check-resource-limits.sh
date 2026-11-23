#!/usr/bin/env bash
# =============================================================================
# check-resource-limits.sh — Every container the charts render has requests
# and a memory limit.
#
# The rule is the Kyverno `require-pod-resources` policy's, so a chart that
# passes here is one that policy would not reject once switched to Enforce:
# CPU and memory requests, and a memory limit, on every container and init
# container of every Pod, Deployment, StatefulSet, DaemonSet, Job, ReplicaSet
# and CronJob. A CPU limit is optional.
#
# It judges what Helm RENDERS, subcharts included. Until #129 it grepped each
# values.yaml for the words `resources:`, `limits:` and `requests:`, so one
# block anywhere passed a whole chart — while platform-monitoring rendered six
# containers with nothing set.
#
# platform-deployment is skipped: its subcharts come from GHCR and are judged
# here one by one, from this repository's source. Helm test pods
# (`helm.sh/hook: test`) are skipped too: they run only under `helm test`.
#
# Usage:
#   scripts/check-resource-limits.sh                 # vendor dependencies, check
#   scripts/check-resource-limits.sh --no-update     # assume charts/*/charts is populated
#   scripts/check-resource-limits.sh --charts-dir D  # charts under D (tests)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

CHARTS_DIR="$REPO_ROOT/charts"
UPDATE_DEPS=1
SKIP_CHARTS=(platform-deployment)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --charts-dir) CHARTS_DIR="$2"; shift 2 ;;
    --no-update)  UPDATE_DEPS=0; shift ;;
    -h|--help)
      awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

if [ "$UPDATE_DEPS" -eq 1 ]; then
  helm_home="$(mktemp -d "${TMPDIR:-/tmp}/resource-limits.XXXXXX")"
  trap 'rm -rf "$helm_home"' EXIT
  export HELM_REPOSITORY_CONFIG="$helm_home/repositories.yaml"
  export HELM_REPOSITORY_CACHE="$helm_home/cache"
fi

# violations <rendered manifests> — "<Kind>/<name>  <container>: missing <fields>"
# for every container (init containers included) that lacks a required field.
violations() {
  yq -r '
    select(.kind != null) |
    select(.kind | test("^(Pod|Deployment|StatefulSet|DaemonSet|Job|ReplicaSet|CronJob)$")) |
    select((.metadata.annotations."helm.sh/hook" // "") | test("test") | not) |
    .kind as $k | .metadata.name as $n |
    (
      (select($k == "Pod") | .spec) //
      (select($k == "CronJob") | .spec.jobTemplate.spec.template.spec) //
      .spec.template.spec
    ) as $spec |
    (($spec.initContainers // []) + ($spec.containers // []))[] |
    # The container is bound and the missing fields computed as the main value.
    # In mikefarah yq (v4.54) binding that computed list with `as` came back
    # empty, and a string literal after an empty `select(…)` is still emitted.
    . as $c |
    {
      "requests.cpu": $c.resources.requests.cpu,
      "requests.memory": $c.resources.requests.memory,
      "limits.memory": $c.resources.limits.memory
    } | to_entries | map(select(.value == null) | .key) |
    select(length > 0) |
    $k + "/" + $n + "  " + $c.name + ": missing " + join(", ")
  ' - <<<"$1" | grep -v '^---$' || true
}

errors=0
for chart_dir in "$CHARTS_DIR"/*/; do
  chart_dir="${chart_dir%/}"
  chart="$(basename "$chart_dir")"
  [ -f "$chart_dir/Chart.yaml" ] || continue
  case " ${SKIP_CHARTS[*]} " in *" $chart "*) continue ;; esac

  log_step "$chart"
  if [ "$UPDATE_DEPS" -eq 1 ] && ! chart_deps_build "$chart_dir" 2>/dev/null; then
    log_error "  helm dependency build failed"
    errors=$((errors + 1))
    continue
  fi
  if ! rendered="$(helm template "$chart" "$chart_dir" 2>&1)"; then
    log_error "  helm template failed:"
    printf '%s\n' "$rendered" | sed 's/^/    /' | head -10
    errors=$((errors + 1))
    continue
  fi

  workloads="$(yq -r 'select(.kind != null) | select(.kind | test("^(Pod|Deployment|StatefulSet|DaemonSet|Job|ReplicaSet|CronJob)$")) | .kind' - <<<"$rendered" | grep -c . || true)"
  if [ "$workloads" -eq 0 ]; then
    log_info "  no workload rendered — nothing to check"
    continue
  fi

  found="$(violations "$rendered")"
  if [ -n "$found" ]; then
    printf '%s\n' "$found" | while IFS= read -r line; do log_error "  $line"; done
    errors=$((errors + 1))
  else
    log_ok "  ${workloads} workload(s): every container has requests and a memory limit"
  fi
done

echo ""
if [ "$errors" -gt 0 ]; then
  log_error "$errors chart(s) render containers without requests or a memory limit"
  exit 1
fi
log_ok "Every rendered container has CPU and memory requests and a memory limit"
