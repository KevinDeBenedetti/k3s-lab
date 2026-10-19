#!/usr/bin/env bats
# tests/bats/chart-deps.bats — Unit tests for lib/chart-deps.sh
#
# These helpers decide which pins scripts/check-umbrella-pins.sh looks at. If
# the parser drops a dependency, the check reports "all pins current" while
# silently ignoring the stale one — the exact failure mode the check exists to
# prevent, so the skipped/miscounted cases matter more than the happy path.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/chart-deps.sh"
  FIXTURE="${BATS_TEST_TMPDIR}"
}

# ─── chart_oci_deps ─────────────────────────────────────────────────────────

@test "chart_oci_deps reads name, version and repository" {
  cat > "${FIXTURE}/Chart.yaml" <<'EOF'
apiVersion: v2
name: umbrella
version: 0.15.0
dependencies:
  - name: platform-argocd
    version: 0.14.0
    repository: oci://ghcr.io/acme/charts
    condition: platform-argocd.enabled
EOF
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "$output" = "$(printf 'platform-argocd\t0.14.0\toci://ghcr.io/acme/charts')" ]
}

@test "chart_oci_deps returns every dependency, not just the first" {
  cat > "${FIXTURE}/Chart.yaml" <<'EOF'
dependencies:
  - name: a
    version: 1.0.0
    repository: oci://ghcr.io/acme/charts
  - name: b
    version: 2.0.0
    repository: oci://ghcr.io/acme/charts
  - name: c
    version: 3.0.0
    repository: oci://ghcr.io/acme/charts
EOF
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[2]}" = "$(printf 'c\t3.0.0\toci://ghcr.io/acme/charts')" ]
}

@test "chart_oci_deps skips dependencies from classic HTTP repos" {
  # platform-traefik's traefik subchart is one of these: not addressable
  # through the registry API, so including it would produce a false failure.
  cat > "${FIXTURE}/Chart.yaml" <<'EOF'
dependencies:
  - name: traefik
    version: 41.1.0
    repository: https://traefik.github.io/charts
  - name: platform-vault
    version: 0.14.0
    repository: oci://ghcr.io/acme/charts
EOF
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == platform-vault* ]]
}

@test "chart_oci_deps stops at the end of the dependencies block" {
  # `version:` also appears at the top level and under other keys; picking one
  # up would attribute the wrong pin to the last dependency.
  cat > "${FIXTURE}/Chart.yaml" <<'EOF'
dependencies:
  - name: a
    version: 1.0.0
    repository: oci://ghcr.io/acme/charts
maintainers:
  - name: someone
    version: 9.9.9
home: https://example.invalid
EOF
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = "$(printf 'a\t1.0.0\toci://ghcr.io/acme/charts')" ]
}

@test "chart_oci_deps prints nothing when there is no dependency at all" {
  cat > "${FIXTURE}/Chart.yaml" <<'EOF'
apiVersion: v2
name: leaf
version: 0.15.0
EOF
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "chart_oci_deps reads the real umbrella Chart.yaml" {
  # Guard against a reindentation in the file the check actually reads: all 7
  # subcharts are pinned there and every one of them must be seen.
  run chart_oci_deps "${REPO_ROOT}/charts/platform-deployment/Chart.yaml"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 7 ]
  [[ "$output" == *platform-traefik* ]]
}

# ─── chart_deps / chart_dep_names / chart_name ──────────────────────────────

@test "chart_deps includes non-oci dependencies that chart_oci_deps drops" {
  cat > "${FIXTURE}/Chart.yaml" <<'YAML'
name: wrapper
dependencies:
  - name: traefik
    version: 41.1.0
    repository: https://traefik.github.io/charts
  - name: platform-vault
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
YAML
  run chart_deps "${FIXTURE}/Chart.yaml"
  [ "${#lines[@]}" -eq 2 ]
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "${#lines[@]}" -eq 1 ]
}

@test "chart_dep_names returns every name whatever the repository scheme" {
  # The render check needs all of them: a subchart pulled over HTTP still has
  # to produce manifests.
  cat > "${FIXTURE}/Chart.yaml" <<'YAML'
name: wrapper
dependencies:
  - name: a
    version: 1.0.0
    repository: https://example.invalid/charts
  - name: b
    version: 2.0.0
    repository: oci://ghcr.io/acme/charts
  - name: c
    version: 3.0.0
    repository: "file://../c"
YAML
  run chart_dep_names "${FIXTURE}/Chart.yaml"
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "a" ]
  [ "${lines[2]}" = "c" ]
}

@test "chart_name reads the chart's own name, not a dependency's" {
  cat > "${FIXTURE}/Chart.yaml" <<'YAML'
apiVersion: v2
name: platform-deployment
version: 0.15.0
dependencies:
  - name: platform-argocd
    version: 0.15.0
    repository: oci://ghcr.io/acme/charts
YAML
  run chart_name "${FIXTURE}/Chart.yaml"
  [ "$output" = "platform-deployment" ]
}

@test "chart_dep_names reads the real umbrella Chart.yaml" {
  run chart_dep_names "${REPO_ROOT}/charts/platform-deployment/Chart.yaml"
  [ "${#lines[@]}" -eq 7 ]
}
