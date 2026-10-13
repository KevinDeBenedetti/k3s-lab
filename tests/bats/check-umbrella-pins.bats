#!/usr/bin/env bats
# tests/bats/check-umbrella-pins.bats — the umbrella's pins must equal the
# subcharts' versions in the repository. Reads files only, no registry.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-umbrella-pins.sh"

setup() {
  WORK="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$WORK/charts/platform-deployment" "$WORK/charts/platform-a"
  cat > "$WORK/charts/platform-deployment/Chart.yaml" <<'YAML'
apiVersion: v2
name: platform-deployment
version: 1.0.0
dependencies:
  - name: platform-a
    version: 1.0.0
    repository: oci://ghcr.io/example/charts
YAML
  printf 'apiVersion: v2\nname: platform-a\nversion: 1.0.0\n' > "$WORK/charts/platform-a/Chart.yaml"
}


@test "passes when the pin equals the subchart version" {
  run "$SCRIPT" --chart "$WORK/charts/platform-deployment"
  [ "$status" -eq 0 ]
}

@test "fails when the pin lags the subchart" {
  sed -i.bak 's/^version: 1.0.0/version: 1.1.0/' "$WORK/charts/platform-a/Chart.yaml"
  run "$SCRIPT" --chart "$WORK/charts/platform-deployment"
  [ "$status" -eq 1 ]
  [[ "$output" == *"platform-a"* ]]
}

@test "reads a quoted version with a trailing comment" {
  printf 'apiVersion: v2\nname: platform-a\nversion: "1.0.0" # x\n' > "$WORK/charts/platform-a/Chart.yaml"
  run "$SCRIPT" --chart "$WORK/charts/platform-deployment"
  [ "$status" -eq 0 ]
}

@test "fails when a pinned subchart has no directory" {
  rm -r "$WORK/charts/platform-a"
  run "$SCRIPT" --chart "$WORK/charts/platform-deployment"
  [ "$status" -eq 1 ]
}

@test "passes on the real repository" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
