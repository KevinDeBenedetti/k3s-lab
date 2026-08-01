#!/usr/bin/env bats
# tests/bats/umbrella-render.bats — Tests for scripts/check-umbrella-render.sh
#
# The behaviour under test is discrimination, not counting. The guard this
# replaced accepted any render of 7+ documents; the render that motivated it had
# 17 documents and was missing four whole subcharts, ingress included. So the
# cases that matter are the ones where a plausible-looking render is wrong.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-umbrella-render.sh"

setup() {
  FIXTURE="${BATS_TEST_TMPDIR}"
  mkdir -p "${FIXTURE}/chart"
  cat > "${FIXTURE}/chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: umbrella
version: 0.15.0
dependencies:
  - name: sub-a
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
  - name: sub-b
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
  - name: sub-c
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
EOF
}

# render SUBCHART... — a fake helm render in which each named subchart
# contributes one manifest, using helm's real `# Source:` attribution format.
render() {
  : > "${FIXTURE}/render.yaml"
  for s in "$@"; do
    {
      echo "---"
      echo "# Source: umbrella/charts/${s}/templates/thing.yaml"
      echo "apiVersion: v1"
      echo "kind: ConfigMap"
    } >> "${FIXTURE}/render.yaml"
  done
}

@test "passes when every declared subchart contributed" {
  render sub-a sub-b sub-c
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All 3 subchart(s) contributed"* ]]
}

@test "fails when one subchart contributed nothing, and names it" {
  render sub-a sub-c
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sub-b"* ]]
  [[ "$output" == *"contributed NOTHING"* ]]
}

@test "a high document count does not excuse a missing subchart" {
  # The exact hole in the old guard: volume from the healthy subcharts hid the
  # absence of the others. Here sub-a alone produces 50 manifests.
  : > "${FIXTURE}/render.yaml"
  for _ in $(seq 50); do
    {
      echo "---"
      echo "# Source: umbrella/charts/sub-a/templates/thing.yaml"
      echo "kind: ConfigMap"
    } >> "${FIXTURE}/render.yaml"
  done
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 of 3 subchart(s) produced no manifest"* ]]
}

@test "an empty render is a failure, not a pass" {
  : > "${FIXTURE}/render.yaml"
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Empty render"* ]]
}

@test "a render with no attribution at all fails" {
  printf 'kind: ConfigMap\n' > "${FIXTURE}/render.yaml"
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 1 ]
}

@test "a chart declaring no dependency is a failure, not a vacuous pass" {
  cat > "${FIXTURE}/chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: umbrella
version: 0.15.0
EOF
  render sub-a
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"declares no dependency"* ]]
}

@test "does not credit a subchart whose name is a prefix of another" {
  # `grep sub-a` would also match `sub-ab`; the trailing slash in the pattern is
  # what keeps the attribution honest.
  cat > "${FIXTURE}/chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: umbrella
version: 0.15.0
dependencies:
  - name: sub-a
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
  - name: sub-ab
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
EOF
  render sub-ab
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sub-a — contributed NOTHING"* ]]
}

@test "reads the render from stdin when --render is omitted" {
  render sub-a sub-b sub-c
  run bash -c "'$SCRIPT' --chart '${FIXTURE}/chart' < '${FIXTURE}/render.yaml'"
  [ "$status" -eq 0 ]
}

@test "warns about a subchart rendered but not declared" {
  render sub-a sub-b sub-c sub-rogue
  run "$SCRIPT" --chart "${FIXTURE}/chart" --render "${FIXTURE}/render.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sub-rogue rendered but is not declared"* ]]
}
