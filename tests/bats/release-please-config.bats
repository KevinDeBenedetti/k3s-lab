#!/usr/bin/env bats
# tests/bats/release-please-config.bats — Every chart is its own release-please
# component, and the config says so.
#
# Since 2026-10-08 each chart is versioned independently. The failure this
# guards against is silent: a chart missing from release-please-config.json is
# not an error anywhere — its commits fall outside every component (the root
# excludes charts/), so it never gets a release PR, its version never moves,
# and release-charts never publishes it again. Likewise a manifest entry that
# disagrees with Chart.yaml makes release-please compute the next version from
# the wrong baseline.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CONFIG="${REPO_ROOT}/.github/release/release-please-config.json"
MANIFEST="${REPO_ROOT}/.github/release/.release-please-manifest.json"

charts() {
  for c in "${REPO_ROOT}"/charts/*/Chart.yaml; do
    basename "$(dirname "$c")"
  done
}

@test "every chart is a release-please package with its own component" {
  missing=""
  for chart in $(charts); do
    component="$(jq -r --arg p "charts/$chart" '.packages[$p].component // empty' "$CONFIG")"
    [ "$component" = "$chart" ] || missing="$missing $chart"
  done
  [ -z "$missing" ] || { echo "not a component (or wrong name):$missing"; return 1; }
}

@test "every chart package bumps its own Chart.yaml version" {
  for chart in $(charts); do
    jq -e --arg p "charts/$chart" \
      '.packages[$p]["extra-files"][] | select(.path == "Chart.yaml" and .jsonpath == "$.version")' \
      "$CONFIG" >/dev/null || { echo "$chart: no extra-files entry for \$.version"; return 1; }
  done
}

@test "every chart has a manifest entry equal to its Chart.yaml version" {
  for chart in $(charts); do
    want="$(awk '/^version:/ { print $2; exit }' "${REPO_ROOT}/charts/$chart/Chart.yaml")"
    got="$(jq -r --arg p "charts/$chart" '.[$p] // empty' "$MANIFEST")"
    [ "$got" = "$want" ] || { echo "$chart: manifest '$got' vs Chart.yaml '$want'"; return 1; }
  done
}

@test "no package points at a chart that no longer exists" {
  for path in $(jq -r '.packages | keys[] | select(startswith("charts/"))' "$CONFIG"); do
    [ -f "${REPO_ROOT}/$path/Chart.yaml" ] || { echo "stale package: $path"; return 1; }
  done
}

@test "the toolkit keeps bare vX.Y.Z tags and ignores charts/" {
  # infra pins K3S_LAB_REF=vX.Y.Z and curls lib/ at that tag: a component
  # prefix on the root tag would 404 every one of those URLs.
  [ "$(jq -r '.packages["."]["include-component-in-tag"]' "$CONFIG")" = "false" ]
  jq -e '.packages["."]["exclude-paths"] | index("charts")' "$CONFIG" >/dev/null
}
