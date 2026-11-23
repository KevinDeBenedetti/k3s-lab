#!/usr/bin/env bats
# tests/bats/resource-limits.bats — scripts/check-resource-limits.sh against
# small fixture charts rendered by the real `helm` (no dependencies, so
# --no-update). The check must judge every container Helm renders, not the
# words present in a values file: until #129 one `resources:` block anywhere
# in values.yaml passed a whole chart.
#
# The rule is the Kyverno require-pod-resources policy's: CPU and memory
# requests and a memory limit on every container and init container; a CPU
# limit is optional.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-resource-limits.sh"

setup() {
  CHARTS="${BATS_TEST_TMPDIR}/charts"
  mkdir -p "$CHARTS"
}

# chart <name> <template body> — a chart with one template.
chart() {
  mkdir -p "${CHARTS}/$1/templates"
  printf 'apiVersion: v2\nname: %s\nversion: 0.1.0\n' "$1" >"${CHARTS}/$1/Chart.yaml"
  : >"${CHARTS}/$1/values.yaml"
  printf '%s\n' "$2" >"${CHARTS}/$1/templates/workload.yaml"
}

GOOD='resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {memory: 32Mi}}'

deployment() { # deployment <name> <containers yaml> [<initContainers yaml>]
  cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1}
spec:
  selector: {matchLabels: {app: $1}}
  template:
    metadata: {labels: {app: $1}}
    spec:
      initContainers: ${3:-[]}
      containers: $2
YAML
}

check() { run "$SCRIPT" --charts-dir "$CHARTS" --no-update; }

@test "a chart whose containers all have requests and a memory limit passes" {
  chart good "$(deployment web "[{name: web, image: nginx:1.27, $GOOD}]")"
  check
  [ "$status" -eq 0 ]
  [[ "$output" == *"good"* ]]
}

@test "one compliant block elsewhere no longer hides a container without limits" {
  # The #129 case: the old grep saw `resources:`, `limits:` and `requests:`
  # in the values file and passed the chart.
  chart mixed "$(deployment web "[{name: web, image: nginx:1.27, $GOOD}, {name: sidecar, image: busybox:1.36}]")"
  printf 'web:\n  resources:\n    requests: {cpu: 10m}\n    limits: {memory: 32Mi}\n' >"${CHARTS}/mixed/values.yaml"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Deployment/web"*"sidecar"* ]]
}

@test "the missing fields are named; a CPU limit is not required" {
  chart partial "$(deployment web "[{name: web, image: nginx:1.27, resources: {requests: {memory: 16Mi}, limits: {cpu: 100m}}}]")"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"requests.cpu"* ]]
  [[ "$output" == *"limits.memory"* ]]
  [[ "$output" != *"limits.cpu"* ]]
}

@test "init containers are judged too" {
  chart init "$(deployment web "[{name: web, image: nginx:1.27, $GOOD}]" "[{name: setup, image: busybox:1.36}]")"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"setup"* ]]
}

@test "CronJob containers are judged through the job template" {
  chart cron "$(cat <<'YAML'
apiVersion: batch/v1
kind: CronJob
metadata: {name: nightly}
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers: [{name: run, image: busybox:1.36}]
YAML
)"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"CronJob/nightly"*"run"* ]]
}

@test "a chart that renders no workload passes, and says so" {
  chart empty 'apiVersion: v1
kind: ConfigMap
metadata: {name: settings}
data: {a: "1"}'
  check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no workload"* ]]
}

@test "every failing chart is reported, not only the first" {
  chart one "$(deployment a "[{name: a, image: nginx:1.27}]")"
  chart two "$(deployment b "[{name: b, image: nginx:1.27}]")"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"one"* && "$output" == *"two"* ]]
}

@test "a chart that fails to render is an error, not a pass" {
  chart broken '{{ fail "boom" }}'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken"* ]]
}
