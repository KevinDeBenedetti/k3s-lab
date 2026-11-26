#!/usr/bin/env bats
# tests/bats/platform-monitoring-logs.bats — The log shipper of charts/platform-monitoring
#
# Grafana Alloy replaced the end-of-life promtail subchart on 2026-11-25. Its
# whole pipeline is one string in values.yaml, which no linter here reads: a
# wrong push URL or a missing mount renders fine and ships nothing. These tests
# freeze the parts of it that fail silently.
#
# Offline on purpose: they read Chart.yaml, Chart.lock and values.yaml, never a
# render, because the vendored subcharts (`charts/**/charts/*.tgz`) are
# gitignored and absent from a clean checkout.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHART="${REPO_ROOT}/charts/platform-monitoring"

setup() {
  source "${REPO_ROOT}/lib/chart-deps.sh"
}

alloy_config() {
  yq -r '.alloy.alloy.configMap.content' "${CHART}/values.yaml"
}

@test "the log shipper is alloy, in Chart.yaml and in Chart.lock alike" {
  run chart_dep_names "${CHART}/Chart.yaml"
  [[ $'\n'"$output"$'\n' == *$'\n'alloy$'\n'* ]]
  [[ "$output" != *promtail* ]]
  # A Chart.lock left behind makes `helm dependency build` fail on every check.
  run yq -r '.dependencies[].name' "${CHART}/Chart.lock"
  [[ $'\n'"$output"$'\n' == *$'\n'alloy$'\n'* ]]
  [[ "$output" != *promtail* ]]
}

@test "no values are left under the removed promtail key" {
  # Helm ignores values for a subchart that is not declared: a leftover block
  # would read as configuration and configure nothing.
  run yq -r '.promtail // "absent"' "${CHART}/values.yaml"
  [ "$output" = "absent" ]
}

@test "alloy pushes to the Loki subchart by its short name" {
  # `fullnameOverride: loki` names the service; a namespace-qualified URL only
  # resolves when the chart is installed into that namespace.
  [ "$(yq -r '.loki.fullnameOverride' "${CHART}/values.yaml")" = "loki" ]
  run alloy_config
  [[ "$output" == *'url = "http://loki:3100/loki/api/v1/push"'* ]]
}

@test "the alloy config carries no template braces" {
  # The alloy chart renders the config through `tpl`: a `{{` in it is evaluated
  # as a Helm template, or fails the render.
  run alloy_config
  [ -n "$output" ]
  [[ "$output" != *'{{'* ]]
}

@test "the path alloy tails is mounted from the node, read-only" {
  run alloy_config
  [[ "$output" == *'/var/log/pods/'* ]]
  [ "$(yq -r '.alloy.controller.volumes.extra[] | select(.name == "pods") | .hostPath.path' "${CHART}/values.yaml")" = "/var/log/pods" ]
  [ "$(yq -r '.alloy.alloy.mounts.extra[] | select(.name == "pods") | .mountPath' "${CHART}/values.yaml")" = "/var/log/pods" ]
  [ "$(yq -r '.alloy.alloy.mounts.extra[] | select(.name == "pods") | .readOnly' "${CHART}/values.yaml")" = "true" ]
}

@test "the alloy container declares requests and a memory limit" {
  # scripts/check-resource-limits.sh asserts this on the render, in CI; this is
  # its offline copy for the one container this chart sizes itself.
  [ "$(yq -r '.alloy.alloy.resources.requests.cpu' "${CHART}/values.yaml")" != "null" ]
  [ "$(yq -r '.alloy.alloy.resources.requests.memory' "${CHART}/values.yaml")" != "null" ]
  [ "$(yq -r '.alloy.alloy.resources.limits.memory' "${CHART}/values.yaml")" != "null" ]
}
