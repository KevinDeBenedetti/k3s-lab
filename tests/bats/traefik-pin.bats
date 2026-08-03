#!/usr/bin/env bats
# tests/bats/traefik-pin.bats — Unit tests for lib/traefik-pin.sh
#
# This helper is the single source of the proxy version for both Traefik checks.
# If it picks the wrong key, or stays silent when it should not, both checks are
# wrong together — hence the section-confusion and stale-tarball cases below.
#
# Since 2026-07-30 the chart carries no `traefik.image.tag`: the version comes
# from the subchart's appVersion, and the pin is only the escape hatch for the
# next time an advisory lands ahead of upstream. Both paths are covered here,
# because both are load-bearing.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/traefik-pin.sh"
  # BATS_TEST_TMPDIR is created and cleaned up by bats for each test.
  FIXTURE="${BATS_TEST_TMPDIR}"
}

@test "traefik_pinned_tag strips surrounding quotes" {
  # `tag: "v3.7.10"` and `tag: v3.7.10` are the same pin; downstream checks
  # compare the value against rendered manifests by string equality.
  cat > "${FIXTURE}/values.yaml" <<'EOF'
traefik:
  image:
    tag: "v3.7.10"
EOF
  run traefik_pinned_tag "${FIXTURE}/values.yaml"
  [ "$output" = "v3.7.10" ]
}

traefik_values() {
  cat > "${FIXTURE}/values.yaml" <<EOF
traefik:
$1
  ingressRoute:
    dashboard:
      enabled: false
  metrics:
    prometheus:
      tag: should-never-be-read
EOF
}

# fixture_lock VERSION — a Chart.lock naming that subchart version.
fixture_lock() {
  cat > "${FIXTURE}/Chart.lock" <<EOF
dependencies:
- name: traefik
  repository: https://traefik.github.io/charts
  version: $1
digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
generated: "2026-07-30T09:20:00.000000+02:00"
EOF
}

# fixture_subchart VERSION APPVERSION — a tarball shaped like the real one.
fixture_subchart() {
  mkdir -p "${FIXTURE}/charts" "${FIXTURE}/build/traefik"
  cat > "${FIXTURE}/build/traefik/Chart.yaml" <<EOF
annotations:
  traefik.io/proxy-max-version: $2
apiVersion: v2
appVersion: $2
name: traefik
version: $1
EOF
  tar -czf "${FIXTURE}/charts/traefik-$1.tgz" -C "${FIXTURE}/build" traefik
}

# ─── traefik_pinned_tag ─────────────────────────────────────────────────────

@test "traefik_pinned_tag reads traefik.image.tag" {
  traefik_values "  image:
    tag: v3.7.9"
  run traefik_pinned_tag "${FIXTURE}/values.yaml"
  [ "$output" = "v3.7.9" ]
}

@test "traefik_pinned_tag ignores a tag: from another section" {
  traefik_values "  ingressClass:
    enabled: true"
  run traefik_pinned_tag "${FIXTURE}/values.yaml"
  [ -z "$output" ]
}

@test "traefik_pinned_tag prints nothing when no pin is set" {
  # The normal state since 2026-07-30. The helper must report the absence rather
  # than invent a value: resolving the fallback is traefik_effective_tag's job.
  traefik_values "  image:
    repository: docker.io/traefik"
  run traefik_pinned_tag "${FIXTURE}/values.yaml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "traefik_pinned_tag ignores an image.tag outside the traefik block" {
  cat > "${FIXTURE}/values.yaml" <<'EOF'
somethingElse:
  image:
    tag: v9.9.9
traefik:
  image:
    tag: v3.7.9
EOF
  run traefik_pinned_tag "${FIXTURE}/values.yaml"
  [ "$output" = "v3.7.9" ]
}

# ─── traefik_locked_field ───────────────────────────────────────────────────

@test "traefik_locked_field reads version and repository" {
  fixture_lock "41.1.0"
  run traefik_locked_field "${FIXTURE}" version
  [ "$output" = "41.1.0" ]
  run traefik_locked_field "${FIXTURE}" repository
  [ "$output" = "https://traefik.github.io/charts" ]
}

@test "traefik_locked_field ignores another dependency's fields" {
  cat > "${FIXTURE}/Chart.lock" <<'EOF'
dependencies:
- name: something-else
  repository: https://example.invalid/charts
  version: 9.9.9
- name: traefik
  repository: https://traefik.github.io/charts
  version: 41.1.0
digest: sha256:0000
generated: "2026-07-30T09:20:00.000000+02:00"
EOF
  run traefik_locked_field "${FIXTURE}" version
  [ "$output" = "41.1.0" ]
}

@test "traefik_locked_field reads the real chart Chart.lock" {
  # Guard against a reindentation or a renamed dependency in the actual file:
  # the advisory watch resolves the subchart to fetch through this very field.
  run traefik_locked_field "${REPO_ROOT}/charts/platform-traefik" version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

  run traefik_locked_field "${REPO_ROOT}/charts/platform-traefik" repository
  [[ "$output" =~ ^https:// ]]
}

# ─── traefik_subchart_appversion ────────────────────────────────────────────

@test "traefik_subchart_appversion reads appVersion from the vendored tarball" {
  fixture_lock "41.1.0"
  fixture_subchart "41.1.0" "v3.7.9"
  run traefik_subchart_appversion "${FIXTURE}"
  [ "$output" = "v3.7.9" ]
}

@test "traefik_subchart_appversion prints nothing when the tarball is absent" {
  # A fresh checkout, before `helm dependency build`: the tarball is gitignored.
  fixture_lock "41.1.0"
  run traefik_subchart_appversion "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "traefik_subchart_appversion ignores a tarball left over from another version" {
  # The case a glob would get wrong: a stale tarball is not the locked subchart,
  # and reading its appVersion would report a version we do not deploy.
  fixture_lock "41.1.0"
  fixture_subchart "41.0.2" "v3.7.6"
  run traefik_subchart_appversion "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── traefik_effective_tag ──────────────────────────────────────────────────

@test "traefik_effective_tag falls back to the subchart appVersion" {
  traefik_values "  ingressClass:
    enabled: true"
  fixture_lock "41.1.0"
  fixture_subchart "41.1.0" "v3.7.9"
  run traefik_effective_tag "${FIXTURE}"
  [ "$output" = "v3.7.9" ]
}

@test "traefik_effective_tag prefers the pin over the appVersion" {
  # The escape hatch: when an advisory lands ahead of upstream we pin again, and
  # both checks must then follow the pin, not the chart we are overriding.
  traefik_values "  image:
    tag: v3.8.1"
  fixture_lock "41.1.0"
  fixture_subchart "41.1.0" "v3.7.9"
  run traefik_effective_tag "${FIXTURE}"
  [ "$output" = "v3.8.1" ]
}

@test "traefik_effective_tag prints nothing when nothing is resolvable" {
  # No pin and no subchart: the version is unknown. Callers must fail on this
  # silence — an unknown version is not a safe version.
  traefik_values "  ingressClass:
    enabled: true"
  fixture_lock "41.1.0"
  run traefik_effective_tag "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── published-chart layout (subchart expanded, not a tarball) ──────────────

# fixture_expanded_subchart VERSION APPVERSION — the layout `helm package`
# produces, which is what a chart pulled back from the registry looks like.
fixture_expanded_subchart() {
  mkdir -p "${FIXTURE}/charts/traefik"
  cat > "${FIXTURE}/charts/traefik/Chart.yaml" <<EOF2
apiVersion: v2
appVersion: $2
name: traefik
version: $1
EOF2
}

@test "traefik_subchart_appversion reads an expanded subchart directory" {
  # check-deployed-traefik.sh inspects charts pulled from GHCR, where the
  # subchart is embedded expanded rather than as a tarball.
  fixture_lock "41.0.2"
  fixture_expanded_subchart "41.0.2" "v3.7.6"
  run traefik_subchart_appversion "${FIXTURE}"
  [ "$output" = "v3.7.6" ]
}

@test "traefik_subchart_appversion rejects an expanded subchart of the wrong version" {
  # The expanded form carries no version in its path, so its own version: is
  # what stops a mismatched directory being read as the truth.
  fixture_lock "41.1.0"
  fixture_expanded_subchart "41.0.2" "v3.7.6"
  run traefik_subchart_appversion "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "traefik_subchart_appversion prefers the tarball when both layouts exist" {
  fixture_lock "41.1.0"
  fixture_subchart "41.1.0" "v3.7.9"
  fixture_expanded_subchart "41.1.0" "v9.9.9"
  run traefik_subchart_appversion "${FIXTURE}"
  [ "$output" = "v3.7.9" ]
}
