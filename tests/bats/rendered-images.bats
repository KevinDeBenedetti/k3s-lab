#!/usr/bin/env bats
# tests/bats/rendered-images.bats — Tests for scripts/check-rendered-images.sh
#
# The behaviour under test is that a *decorative* pin fails. Audit finding 8 was
# a pin (hashicorp/vault 1.21.2) that no longer described what shipped, and the
# reason nothing noticed is that every other check in this repo is satisfied by
# a pin merely being syntactically present. So the cases that matter here are
# the ones where values.yaml looks entirely correct and is not.
#
# Fixtures are local charts with no dependencies, so `--no-update` keeps the
# whole file offline — no `helm repo add`, no network.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-rendered-images.sh"

setup() {
  CHARTS="${BATS_TEST_TMPDIR}/charts"
  mkdir -p "${CHARTS}/demo/templates"
  cat > "${CHARTS}/demo/Chart.yaml" <<'EOF'
apiVersion: v2
name: demo
version: 0.1.0
EOF
}

# values REPO TAG — the pin as an operator would write it.
values() {
  cat > "${CHARTS}/demo/values.yaml" <<EOF
app:
  image:
    repository: $1
    tag: "$2"
    pullPolicy: IfNotPresent
EOF
}

# template EXPR — what the chart actually renders for the image field.
template() {
  cat > "${CHARTS}/demo/templates/deploy.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: demo
spec:
  containers:
    - name: app
      image: $1
EOF
}

run_check() {
  run "$SCRIPT" --no-update --charts-dir "$CHARTS" "$@"
}

@test "passes when the rendered tag matches the pin" {
  values acme/api 1.4.2
  template '{{ .Values.app.image.repository }}:{{ .Values.app.image.tag }}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"acme/api:1.4.2"* ]]
  [[ "$output" == *"All 1 image pin(s) reach the render"* ]]
}

@test "fails when the template ignores the pin — the finding-8 shape" {
  # values.yaml says 1.4.2; the chart hardcodes 1.0.0, exactly what happens when
  # a subchart renames the key the pin lives under. The pin is still valid YAML,
  # still linted, still reviewed — and completely inert.
  values acme/api 1.4.2
  template 'acme/api:1.0.0'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"acme/api:1.0.0"* ]]
  [[ "$output" == *"pins tag 1.4.2"* ]]
}

@test "fails when the pinned repository appears nowhere in the render" {
  # The other way a pin goes decorative: the workload it described was removed
  # or renamed, so nothing carries the image at all. Zero matches must not read
  # as "nothing to check".
  values acme/api 1.4.2
  template 'other/thing:9.9.9'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"absent from the render"* ]]
  [[ "$output" == *"decorative"* ]]
}

@test "quoted and unquoted tags compare equal" {
  # `tag: "1.32"` in values vs `image: repo:1.32` in the render is a match;
  # comparing the raw strings would make the quotes a false failure.
  values acme/api 1.32
  template '{{ .Values.app.image.repository }}:{{ .Values.app.image.tag }}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"acme/api:1.32"* ]]
}

@test "a registry-qualified render still matches a bare repository pin" {
  # values.yaml pins `acme/api`; the chart renders `ghcr.io/acme/api`. Same
  # image — the registry prefix must not be read as a different repository.
  values acme/api 1.4.2
  template 'ghcr.io/acme/api:1.4.2'
  run_check
  [ "$status" -eq 0 ]
}

@test "does not confuse a repository that is a prefix of another" {
  # `hashicorp/vault` must not be satisfied by `hashicorp/vault-k8s`. This is the
  # real pairing in charts/platform-vault, and a substring match would pass it
  # while the actual Vault image drifted.
  values acme/api 1.4.2
  template 'acme/api-sidecar:0.0.1'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"absent from the render"* ]]
}

@test "a repository and a tag at different depths are not paired" {
  # `repository:` under one block and `tag:` under the next is not a pin. Pairing
  # them would invent a constraint the chart never declared and fail on it.
  #
  # The `extra.tag` must ALSO not be read as a tag-only pin: tag-only extraction
  # only fires when the parent key is `image:`, which is exactly what keeps that
  # shape from turning every bare `tag:` in a values file into a constraint.
  cat > "${CHARTS}/demo/values.yaml" <<'EOF'
app:
  image:
    repository: acme/api
  extra:
    tag: "nonsense"
EOF
  template 'acme/api:1.4.2'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"No image pin"* ]]
}

@test "finding no pin anywhere is a failure, not a vacuous pass" {
  # A check that silently asserts nothing is how finding 8 survived. If the pins
  # vanish, that is a signal, not a clean run.
  cat > "${CHARTS}/demo/values.yaml" <<'EOF'
app:
  replicas: 1
EOF
  template 'acme/api:1.4.2'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to assert"* ]]
}

@test "an inline comment after the tag is not part of the tag" {
  values acme/api 1.4.2
  cat > "${CHARTS}/demo/values.yaml" <<'EOF'
app:
  image:
    repository: acme/api   # upstream registry
    tag: "1.4.2"           # bumped 2026-08-06
EOF
  template 'acme/api:1.4.2'
  run_check
  [ "$status" -eq 0 ]
}

@test "a failing render is reported, not swallowed" {
  values acme/api 1.4.2
  template '{{ .Values.does.not.exist }}'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"helm template failed"* ]]
}

# ─── Tag-only pins (the traefik shape) ──────────────────────────────────────
# `traefik.image.tag` with no `repository:` sibling. Until 2026-08-15 this
# script saw nothing at all in such a chart and reported it as "declares no
# pins" — a clean run over a file that does pin an image is the same vacuous
# pass finding 8 was made of.

# tag_only_values TAG — a bare tag under an image: mapping, no repository.
tag_only_values() {
  cat > "${CHARTS}/demo/values.yaml" <<EOF
traefik:
  image:
    tag: "$1"
    pullPolicy: IfNotPresent
EOF
}

@test "a bare image.tag pin is checked, not ignored" {
  tag_only_values v3.7.10
  template 'docker.io/traefik:v3.7.10'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag-only pin"* ]]
  [[ "$output" == *"All 1 image pin(s) reach the render"* ]]
}

@test "a bare image.tag pin fails when the render carries a different tag" {
  # The finding-8 shape for a chart that names no repository.
  tag_only_values v3.7.10
  template 'docker.io/traefik:v3.0.0'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no rendered image carries this tag"* ]]
  [[ "$output" == *"docker.io/traefik:v3.0.0"* ]]
}

@test "a bare image.tag pin fails when no image matches the hint at all" {
  tag_only_values v3.7.10
  template 'acme/unrelated:v3.7.10'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"absent from the render"* ]]
  [[ "$output" == *"decorative"* ]]
}

@test "the hint matches the last path component, not the registry" {
  # A `traefik` hint must not be satisfied by a registry or org that happens to
  # contain the word while the image itself is something else entirely.
  tag_only_values v3.7.10
  template 'traefik.io/some/other:v3.7.10'
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"absent from the render"* ]]
}

@test "one matching image is enough when the hint matches several" {
  # A chart named traefik shipping both the proxy and a traefik-prefixed sidecar:
  # requiring every hint match to carry the pinned tag would fail a correct chart.
  tag_only_values v3.7.10
  cat > "${CHARTS}/demo/templates/deploy.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: demo
spec:
  containers:
    - name: proxy
      image: docker.io/traefik:v3.7.10
    - name: sidecar
      image: acme/traefik-helper:0.1.0
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "a nested component key is usable as a hint too" {
  # `vault.server.image.tag` — the image is named after the chart, not the
  # component, so every ancestor is offered as a hint rather than just the parent.
  cat > "${CHARTS}/demo/values.yaml" <<'EOF'
vault:
  server:
    image:
      tag: "1.21.4"
EOF
  template 'hashicorp/vault:1.21.4'
  run_check
  [ "$status" -eq 0 ]
}

@test "an image: mapping with both repository and tag is not double-counted" {
  # The repo branch must consume the tag, or every ordinary pin would also
  # register as a tag-only pin and be checked twice.
  values acme/api 1.4.2
  template '{{ .Values.app.image.repository }}:{{ .Values.app.image.tag }}'
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"All 1 image pin(s) reach the render"* ]]
  [[ "$output" != *"tag-only pin"* ]]
}

@test "checks every chart under the directory, not just the first" {
  values acme/api 1.4.2
  template '{{ .Values.app.image.repository }}:{{ .Values.app.image.tag }}'

  mkdir -p "${CHARTS}/second/templates"
  cat > "${CHARTS}/second/Chart.yaml" <<'EOF'
apiVersion: v2
name: second
version: 0.1.0
EOF
  cat > "${CHARTS}/second/values.yaml" <<'EOF'
app:
  image:
    repository: acme/worker
    tag: "2.0.0"
EOF
  cat > "${CHARTS}/second/templates/deploy.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: second
spec:
  containers:
    - name: app
      image: acme/worker:1.0.0
EOF

  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"acme/worker:1.0.0"* ]]
  [[ "$output" == *"pins tag 2.0.0"* ]]
}
