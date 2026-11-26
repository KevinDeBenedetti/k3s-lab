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

@test "chart_deps_build registers each http repository once, then builds" {
  mkdir -p "${BATS_TEST_TMPDIR}/mychart"
  cat >"${BATS_TEST_TMPDIR}/mychart/Chart.yaml" <<'YAML'
apiVersion: v2
name: mychart
version: 0.1.0
dependencies:
  - name: a
    version: 1.0.0
    repository: https://charts.example.test
  - name: b
    version: 2.0.0
    repository: https://charts.example.test
  - name: c
    version: 3.0.0
    repository: oci://ghcr.io/example/charts
YAML
  calls="${BATS_TEST_TMPDIR}/helm-calls"
  printf '#!/usr/bin/env bash\necho "$*" >>%q\n' "$calls" >"${BATS_TEST_TMPDIR}/helm"
  chmod +x "${BATS_TEST_TMPDIR}/helm"
  HELM="${BATS_TEST_TMPDIR}/helm" chart_deps_build "${BATS_TEST_TMPDIR}/mychart"
  [ "$(grep -c '^repo add' "$calls")" -eq 1 ]
  grep -q '^repo add mychart-dep1 https://charts.example.test --force-update$' "$calls"
  [ "$(tail -n 1 "$calls")" = "dependency build ${BATS_TEST_TMPDIR}/mychart" ]
}

@test "chart_deps strips the quotes around a field" {
  # `repository: "https://…"` is valid YAML and Helm accepts it. Printed with
  # its quotes, the URL is no longer recognised as http(s) by chart_deps_build,
  # nor as oci:// by chart_oci_deps.
  cat > "${FIXTURE}/Chart.yaml" <<'YAML'
name: wrapper
dependencies:
  - name: "a"
    version: "1.0.0"
    repository: "https://charts.example.test"
  - name: 'b'
    version: '2.0.0'
    repository: 'oci://ghcr.io/acme/charts'
YAML
  run chart_deps "${FIXTURE}/Chart.yaml"
  [ "${lines[0]}" = "$(printf 'a\t1.0.0\thttps://charts.example.test')" ]
  [ "${lines[1]}" = "$(printf 'b\t2.0.0\toci://ghcr.io/acme/charts')" ]
  run chart_oci_deps "${FIXTURE}/Chart.yaml"
  [ "$output" = "$(printf 'b\t2.0.0\toci://ghcr.io/acme/charts')" ]
}

@test "chart_deps_build registers a quoted http repository like an unquoted one" {
  # One readable and one quoted repository: before the quotes were stripped,
  # the guard below stayed silent (one repository was parsed) and helm ended on
  # "no repository definition" for the quoted one.
  mkdir -p "${BATS_TEST_TMPDIR}/mychart"
  cat >"${BATS_TEST_TMPDIR}/mychart/Chart.yaml" <<'YAML'
apiVersion: v2
name: mychart
version: 0.1.0
dependencies:
  - name: a
    version: 1.0.0
    repository: https://charts.example.test
  - name: b
    version: 2.0.0
    repository: "https://quoted.example.test"
  - name: c
    version: 3.0.0
    repository: 'https://single.example.test'
YAML
  calls="${BATS_TEST_TMPDIR}/helm-calls"
  printf '#!/usr/bin/env bash\necho "$*" >>%q\n' "$calls" >"${BATS_TEST_TMPDIR}/helm"
  chmod +x "${BATS_TEST_TMPDIR}/helm"
  HELM="${BATS_TEST_TMPDIR}/helm" chart_deps_build "${BATS_TEST_TMPDIR}/mychart"
  [ "$(grep -c '^repo add' "$calls")" -eq 3 ]
  grep -q '^repo add mychart-dep[0-9] https://quoted.example.test --force-update$' "$calls"
  grep -q '^repo add mychart-dep[0-9] https://single.example.test --force-update$' "$calls"
  [ "$(tail -n 1 "$calls")" = "dependency build ${BATS_TEST_TMPDIR}/mychart" ]
}

@test "chart_deps_build refuses an http repository it could not read, before helm runs" {
  # A flow-style list is valid YAML that the line parser can never read: it
  # sees no `- name:` line, so no dependency and no repository. Building anyway
  # would fail later with helm's cryptic "no repository definition":
  # registering nothing is the bug, not a valid state.
  mkdir -p "${BATS_TEST_TMPDIR}/mychart"
  cat >"${BATS_TEST_TMPDIR}/mychart/Chart.yaml" <<'YAML'
apiVersion: v2
name: mychart
version: 0.1.0
dependencies: [{name: a, version: 1.0.0, repository: https://charts.example.test}]
YAML
  calls="${BATS_TEST_TMPDIR}/helm-calls"
  printf '#!/usr/bin/env bash\necho "$*" >>%q\n' "$calls" >"${BATS_TEST_TMPDIR}/helm"
  chmod +x "${BATS_TEST_TMPDIR}/helm"
  run env HELM="${BATS_TEST_TMPDIR}/helm" bash -c "source '${REPO_ROOT}/lib/chart-deps.sh'; chart_deps_build '${BATS_TEST_TMPDIR}/mychart'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mychart/Chart.yaml declares an http(s) repository"* ]]
  [ ! -e "$calls" ]
}

@test "chart_deps_build returns helm's failure" {
  mkdir -p "${BATS_TEST_TMPDIR}/mychart"
  printf 'apiVersion: v2\nname: mychart\nversion: 0.1.0\n' >"${BATS_TEST_TMPDIR}/mychart/Chart.yaml"
  printf '#!/usr/bin/env bash\n[ "$1" != dependency ]\n' >"${BATS_TEST_TMPDIR}/helm"
  chmod +x "${BATS_TEST_TMPDIR}/helm"
  run env HELM="${BATS_TEST_TMPDIR}/helm" bash -c "source '${REPO_ROOT}/lib/chart-deps.sh'; chart_deps_build '${BATS_TEST_TMPDIR}/mychart'"
  [ "$status" -ne 0 ]
}

# ─── chart_deps_isolate ─────────────────────────────────────────────────────

@test "chart_deps_isolate points helm at a throwaway repository config" {
  caller="${BATS_TEST_TMPDIR}/caller/repositories.yaml"
  run env HELM_REPOSITORY_CONFIG="$caller" TMPDIR="$BATS_TEST_TMPDIR" bash -c "
    source '${REPO_ROOT}/lib/chart-deps.sh'
    chart_deps_isolate demo-check
    printf '%s\n%s\n%s\n' \"\$CHART_DEPS_HOME\" \"\$HELM_REPOSITORY_CONFIG\" \"\$HELM_REPOSITORY_CACHE\"
    [ -d \"\$CHART_DEPS_HOME\" ]
  "
  [ "$status" -eq 0 ]
  home="${lines[0]}"
  [[ "$home" == "${BATS_TEST_TMPDIR}/demo-check."* ]]
  [ "${lines[1]}" = "$home/repositories.yaml" ]
  [ "${lines[2]}" = "$home/cache" ]
}

@test "chart_deps_isolate leaves the caller's config untouched and cleans up on exit" {
  # A `helm repo add` under the isolation must not reach the caller's
  # repositories.yaml, and the throwaway directory must not outlive the script.
  mkdir -p "${BATS_TEST_TMPDIR}/caller"
  caller="${BATS_TEST_TMPDIR}/caller/repositories.yaml"
  printf 'repositories: []\n' >"$caller"
  printf '#!/usr/bin/env bash\necho "$*" >>"$HELM_REPOSITORY_CONFIG"\n' >"${BATS_TEST_TMPDIR}/helm"
  chmod +x "${BATS_TEST_TMPDIR}/helm"
  run env HELM_REPOSITORY_CONFIG="$caller" HELM="${BATS_TEST_TMPDIR}/helm" TMPDIR="$BATS_TEST_TMPDIR" bash -c "
    source '${REPO_ROOT}/lib/chart-deps.sh'
    chart_deps_isolate demo-check
    \"\$HELM\" repo add x https://charts.example.test
    grep -q 'repo add x' \"\$HELM_REPOSITORY_CONFIG\"
    echo \"\$CHART_DEPS_HOME\"
  "
  [ "$status" -eq 0 ]
  [ "$(cat "$caller")" = "repositories: []" ]
  [[ "$output" == "${BATS_TEST_TMPDIR}/demo-check."* ]]
  [ ! -e "$output" ]
}

@test "chart_deps_isolate cleans up when the script fails" {
  run env TMPDIR="$BATS_TEST_TMPDIR" bash -c "
    set -e
    source '${REPO_ROOT}/lib/chart-deps.sh'
    chart_deps_isolate demo-check
    echo \"\$CHART_DEPS_HOME\"
    false
  "
  [ "$status" -ne 0 ]
  [[ "$output" == "${BATS_TEST_TMPDIR}/demo-check."* ]]
  [ ! -e "$output" ]
}

@test "chart_deps_isolate fails, and changes nothing, when it cannot create its directory" {
  # A TMPDIR that does not exist: mktemp fails. The caller's config must stay
  # in place rather than point into a directory that was never created.
  run env HELM_REPOSITORY_CONFIG=/caller/repositories.yaml TMPDIR="${BATS_TEST_TMPDIR}/missing" bash -c "
    source '${REPO_ROOT}/lib/chart-deps.sh'
    chart_deps_isolate demo-check && exit 99
    echo \"\$HELM_REPOSITORY_CONFIG\"
    trap -p EXIT
  "
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "/caller/repositories.yaml" ]
}
