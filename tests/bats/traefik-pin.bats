#!/usr/bin/env bats
# tests/bats/traefik-pin.bats — Unit tests for lib/traefik-pin.sh
#
# This helper is the single source of the pin for both Traefik checks. If it
# picks the wrong key, or stays silent when it should not, both checks are wrong
# together — hence the section-confusion cases below.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/traefik-pin.sh"
  # BATS_TEST_TMPDIR is created and cleaned up by bats for each test.
  FIXTURE="${BATS_TEST_TMPDIR}"
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

@test "traefik_pinned_tag prints nothing when the pin is absent" {
  # Critical case: without image.tag the subchart falls back to its appVersion.
  # The helper must make that silence visible, not invent a value.
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

@test "traefik_pinned_tag reads the real chart values.yaml" {
  # Guard against a reindentation or a moved key in the actual chart: that file
  # is the one both checks read in production.
  run traefik_pinned_tag "${REPO_ROOT}/charts/platform-traefik/values.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
