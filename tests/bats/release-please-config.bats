#!/usr/bin/env bats
# tests/bats/release-please-config.bats — The whole repository shares one
# version, and the config says where it is written.
#
# release-please runs a single component. Every charts/*/Chart.yaml and every
# pin of the umbrella is an extra-file of that component. The failure this
# guards against is silent: a chart missing from extra-files is not an error
# anywhere — its version just stops moving while the rest of the repository
# advances, and the umbrella ends up pinning a stale subchart.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CONFIG="${REPO_ROOT}/.github/release/release-please-config.json"
MANIFEST="${REPO_ROOT}/.github/release/.release-please-manifest.json"

charts() {
  for c in "${REPO_ROOT}"/charts/*/Chart.yaml; do
    basename "$(dirname "$c")"
  done
}

chart_version() {
  awk '/^version:/ { print $2; exit }' "${REPO_ROOT}/charts/$1/Chart.yaml"
}

@test "there is a single release-please package, the repository root" {
  [ "$(jq -r '.packages | keys | join(",")' "$CONFIG")" = "." ]
}

@test "the root keeps bare vX.Y.Z tags" {
  # Consumers check out this repository at vX.Y.Z (Ansible roles, scripts):
  # a component prefix on the tag would break every one of those refs.
  [ "$(jq -r '.packages["."]["include-component-in-tag"]' "$CONFIG")" = "false" ]
}

@test "every chart's Chart.yaml version is an extra-file of the root package" {
  for chart in $(charts); do
    jq -e --arg p "charts/$chart/Chart.yaml" \
      '.packages["."]["extra-files"][] | select(.path == $p and .jsonpath == "$.version")' \
      "$CONFIG" >/dev/null || { echo "$chart: no extra-files entry for \$.version"; return 1; }
  done
}

@test "the umbrella's dependency pins are bumped with the release" {
  jq -e '.packages["."]["extra-files"][]
    | select(.path == "charts/platform-deployment/Chart.yaml" and .jsonpath == "$.dependencies[*].version")' \
    "$CONFIG" >/dev/null
}

@test "no extra-file points at a chart that no longer exists" {
  for path in $(jq -r '.packages["."]["extra-files"][].path | select(startswith("charts/"))' "$CONFIG" | sort -u); do
    [ -f "${REPO_ROOT}/$path" ] || { echo "stale extra-file: $path"; return 1; }
  done
}

@test "every chart sits at the manifest version" {
  want="$(jq -r '.["."]' "$MANIFEST")"
  for chart in $(charts); do
    got="$(chart_version "$chart")"
    [ "$got" = "$want" ] || { echo "$chart: Chart.yaml '$got' vs manifest '$want'"; return 1; }
  done
}

@test "the manifest tracks the root package only" {
  [ "$(jq -r 'keys | join(",")' "$MANIFEST")" = "." ]
}

@test "the umbrella pins every platform-* chart at the shared version" {
  # '$.dependencies[*].version' rewrites every dependency of the umbrella, so
  # each one must be a platform-* chart of this repository.
  want="$(jq -r '.["."]' "$MANIFEST")"
  umbrella="${REPO_ROOT}/charts/platform-deployment/Chart.yaml"
  while IFS=$'\t' read -r name version _; do
    case "$name" in platform-*) ;; *) echo "non-platform dependency: $name"; return 1 ;; esac
    [ "$version" = "$want" ] || { echo "$name: pin '$version' vs shared '$want'"; return 1; }
    [ -f "${REPO_ROOT}/charts/$name/Chart.yaml" ] || { echo "$name: no chart in this repo"; return 1; }
  done < <(source "${REPO_ROOT}/lib/chart-deps.sh"; chart_deps "$umbrella")
}

@test "the umbrella's own version and appVersion are extra-files too" {
  for jp in '$.version' '$.appVersion'; do
    jq -e --arg jp "$jp" '.packages["."]["extra-files"][]
      | select(.path == "charts/platform-deployment/Chart.yaml" and .jsonpath == $jp)' \
      "$CONFIG" >/dev/null || { echo "missing $jp"; return 1; }
  done
}
