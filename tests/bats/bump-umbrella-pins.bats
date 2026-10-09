#!/usr/bin/env bats
# tests/bats/bump-umbrella-pins.bats — Tests for scripts/bump-umbrella-pins.sh
#
# This script is the only thing in the repository allowed to *write* the
# umbrella's pins, and it feeds an automated PR. The failure that matters is
# not a crash — it is a rewrite that silently touches the wrong line: bumping
# the chart's own `version:` would fight release-please, moving a pin nobody
# asked for would ship an untested subchart, and dropping a dependency would
# make check-umbrella-pins.sh report on fewer pins than the chart declares.
# Hence the tests lean on what must NOT change.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/bump-umbrella-pins.sh"

setup() {
  FIXTURE="${BATS_TEST_TMPDIR}"
  mkdir -p "${FIXTURE}/umbrella"
  cat > "${FIXTURE}/umbrella/Chart.yaml" <<'EOF'
apiVersion: v2
name: platform-deployment
description: |
  Umbrella chart.

  Not a dependency:
  - name: decoy-in-description
version: 0.16.0
appVersion: 0.16.0
dependencies:
  - name: platform-argocd
    version: 0.16.0
    repository: oci://ghcr.io/acme/charts
    condition: platform-argocd.enabled
  - name: platform-traefik
    version: 0.16.0
    repository: oci://ghcr.io/acme/charts
    condition: platform-traefik.enabled
maintainers:
  - name: Someone
EOF
  cp "${FIXTURE}/umbrella/Chart.yaml" "${FIXTURE}/orig.yaml"
}

@test "bumps each named dependency to its own version" {
  run "$SCRIPT" --set platform-argocd=0.17.0 --set platform-traefik=0.18.2 \
    --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  source "${REPO_ROOT}/lib/chart-deps.sh"
  run chart_deps "${FIXTURE}/umbrella/Chart.yaml"
  [ "$(printf '%s\n' "${lines[0]}" | cut -f1,2)" = "platform-argocd"$'\t'"0.17.0" ]
  [ "$(printf '%s\n' "${lines[1]}" | cut -f1,2)" = "platform-traefik"$'\t'"0.18.2" ]
}

@test "leaves dependencies without a target untouched" {
  # Independent versioning: publishing platform-traefik says nothing about
  # platform-argocd, whose pin must keep its value.
  run "$SCRIPT" --set platform-traefik=0.17.0 --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  sed '/name: platform-traefik/{n;s/version: 0.16.0/version: 0.17.0/;}' \
    "${FIXTURE}/orig.yaml" > "${FIXTURE}/expected.yaml"
  diff "${FIXTURE}/expected.yaml" "${FIXTURE}/umbrella/Chart.yaml"
}

@test "ignores a name the umbrella does not declare" {
  # release-charts may pass charts that are not subcharts (platform-base).
  run "$SCRIPT" --set platform-base=0.30.0 --set platform-argocd=0.17.0 \
    --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  run grep -c '0.30.0' "${FIXTURE}/umbrella/Chart.yaml"
  [ "$output" = "0" ]
}

@test "leaves the chart's own version and appVersion untouched" {
  # Those two lines belong to release-please; touching them would make the
  # bot and this script overwrite each other's work.
  run "$SCRIPT" --set platform-argocd=0.17.0 --set platform-traefik=0.17.0 \
    --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  grep -q '^version: 0.16.0$' "${FIXTURE}/umbrella/Chart.yaml"
  grep -q '^appVersion: 0.16.0$' "${FIXTURE}/umbrella/Chart.yaml"
}

@test "changes nothing but the dependency version lines" {
  sed 's/^    version: 0.16.0$/    version: 0.17.0/' \
    "${FIXTURE}/orig.yaml" > "${FIXTURE}/expected.yaml"
  run "$SCRIPT" --set platform-argocd=0.17.0 --set platform-traefik=0.17.0 \
    --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  diff "${FIXTURE}/expected.yaml" "${FIXTURE}/umbrella/Chart.yaml"
}

@test "is idempotent — a second run reports nothing to do" {
  run "$SCRIPT" --set platform-argocd=0.17.0 --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  run "$SCRIPT" --set platform-argocd=0.17.0 --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "preserves the dependency count" {
  source "${REPO_ROOT}/lib/chart-deps.sh"
  run "$SCRIPT" --set platform-argocd=0.17.0 --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 0 ]
  run chart_dep_names "${FIXTURE}/umbrella/Chart.yaml"
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "platform-argocd" ]
  [ "${lines[1]}" = "platform-traefik" ]
}

@test "refuses a version that is not release-shaped" {
  # The caller passes what the registry serves; anything else reaching this
  # script is a wiring bug, and writing it into the pins would produce an
  # unresolvable umbrella — the exact 0.13.x freeze.
  run "$SCRIPT" --set platform-argocd=latest --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 2 ]
}

@test "requires at least one --set" {
  run "$SCRIPT" --chart "${FIXTURE}/umbrella"
  [ "$status" -eq 2 ]
}

@test "fails on a chart without dependencies" {
  mkdir -p "${FIXTURE}/empty"
  cat > "${FIXTURE}/empty/Chart.yaml" <<'EOF'
apiVersion: v2
name: not-an-umbrella
version: 0.16.0
EOF
  run "$SCRIPT" --set platform-argocd=0.17.0 --chart "${FIXTURE}/empty"
  [ "$status" -eq 1 ]
}

@test "fails cleanly when the chart directory does not exist" {
  run "$SCRIPT" --set platform-argocd=0.17.0 --chart "${FIXTURE}/nope"
  [ "$status" -eq 2 ]
}
