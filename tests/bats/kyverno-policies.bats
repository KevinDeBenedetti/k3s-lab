#!/usr/bin/env bats
# tests/bats/kyverno-policies.bats — the platform-security Kyverno policies
# evaluated with the Kyverno CLI against tests/fixtures/kyverno/<policy>.yaml:
# every pod named fail-* must fail its policy, and no pod named pass-* may.
#
# This is what proves the policies still EXECUTE, which a render cannot: a
# Kyverno release that drops a policy type keeps rendering it fine (#126). The
# CLI is skipped where it is not installed, except with KYVERNO_REQUIRED=1:
# the `kyverno-policies` CI job sets it, so a runner without the CLI fails
# instead of passing every test by skipping it.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHART_SRC="${REPO_ROOT}/charts/platform-security"
FIXTURES="${REPO_ROOT}/tests/fixtures/kyverno"

setup_file() {
  command -v kyverno >/dev/null 2>&1 || return 0
  # Render the policies without the subcharts (same trick as
  # platform-security-render.bats: Chart.yaml cut before `dependencies:`).
  CHART="${BATS_FILE_TMPDIR}/chart"
  cp -R "$CHART_SRC" "$CHART"
  rm -rf "${CHART}/charts" "${CHART}/Chart.lock"
  awk '/^dependencies:/{exit} {print}' "${CHART_SRC}/Chart.yaml" >"${CHART}/Chart.yaml"
  helm template ps "$CHART" --set kyverno.enabled=true --set kyvernoPolicies.enabled=true \
    >"${BATS_FILE_TMPDIR}/rendered.yaml"
}

setup() {
  if ! command -v kyverno >/dev/null 2>&1; then
    [[ -z "${KYVERNO_REQUIRED:-}" ]] || { echo "KYVERNO_REQUIRED is set and the kyverno CLI is missing" >&2; return 1; }
    skip "needs the kyverno CLI"
  fi
}

# check <policy> — apply it to its fixtures; compare failures with the names.
check() {
  local policy="$1" policy_file="${BATS_TEST_TMPDIR}/${1}.yaml"
  yq "select(.metadata.name == \"${policy}\")" "${BATS_FILE_TMPDIR}/rendered.yaml" >"$policy_file"
  [ -s "$policy_file" ] || { echo "policy ${policy} not rendered"; return 1; }
  run kyverno apply "$policy_file" --resource "${FIXTURES}/${policy}.yaml"
  if [[ "$output" == *"rror"* && "$output" != *"error: 0"* ]]; then
    echo "$output"; return 1
  fi
  local failed expected
  failed="$(grep -oE 'resource apps/Pod/[a-z0-9-]+ failed' <<<"$output" | awk -F/ '{print $3}' | awk '{print $1}' | sort -u)"
  expected="$(yq -r '.metadata.name' "${FIXTURES}/${policy}.yaml" | grep '^fail-' | sort -u)"
  if [[ "$failed" != "$expected" ]]; then
    echo "policy ${policy}"
    echo "expected to fail:"; echo "$expected"
    echo "actually failed:";  echo "$failed"
    echo "--- kyverno output:"; echo "$output"
    return 1
  fi
}

@test "disallow-privilege-escalation" { check disallow-privilege-escalation; }
@test "require-non-root"              { check require-non-root; }
@test "restrict-capabilities"         { check restrict-capabilities; }
@test "require-ro-rootfs"             { check require-ro-rootfs; }
@test "disallow-latest-tag"           { check disallow-latest-tag; }
@test "require-pod-resources"         { check require-pod-resources; }
