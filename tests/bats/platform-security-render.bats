#!/usr/bin/env bats
# tests/bats/platform-security-render.bats — Render contract for charts/platform-security
#
# Why this file exists: until 2026-08-05 this chart shipped six Kyverno
# ClusterPolicies hardcoded to `validationFailureAction: Enforce` and was
# installed on no cluster at all (audit finding 1), so the single most
# consequential value in it — whether a violating pod is *recorded* or
# *rejected* — had never been exercised by anything. The rollout that fixed the
# finding made that value configurable and defaulted it to `Audit`. This file
# freezes that decision so a later edit cannot quietly promote the whole set
# back to `Enforce` and reject pods on the next sync.
#
# ⚠️ Why the chart is copied and stripped instead of rendered in place:
# `charts/**/charts/*.tgz` is gitignored (.gitignore:22), so the vendored
# subcharts exist only on a machine that has run `helm dependency build`. The
# first version of this file rendered the chart directly; it passed locally off
# those leftover tarballs and failed all eight tests on a clean CI checkout,
# where `helm template` cannot resolve the dependencies. Copying the chart and
# deleting its `dependencies:` block removes that hidden requirement: the six
# policies live in this chart's own templates/, so they render with no subchart
# present, no network, and no `helm dependency build`.
#
# The corollary is that nothing here may assert on a subchart's output — that
# would reintroduce the same dependency. The trivy-operator case below is
# therefore checked as a values+condition contract rather than a render.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHART_SRC="${REPO_ROOT}/charts/platform-security"

POLICIES=(
  require-non-root
  require-ro-rootfs
  restrict-capabilities
  disallow-privilege-escalation
  disallow-latest-tag
  require-pod-resources
)

setup() {
  CHART="${BATS_TEST_TMPDIR}/chart"
  cp -R "$CHART_SRC" "$CHART"
  rm -rf "${CHART}/charts" "${CHART}/Chart.lock"
  # `dependencies:` is the last block in Chart.yaml, so truncating at it leaves
  # a valid chart. Asserted below rather than assumed — if upstream reorders the
  # file, this must fail loudly instead of silently rendering nothing.
  awk '/^dependencies:/{exit} {print}' "${CHART_SRC}/Chart.yaml" > "${CHART}/Chart.yaml"
  grep -q '^name: platform-security' "${CHART}/Chart.yaml"
  grep -q '^version:' "${CHART}/Chart.yaml"
}

render() {
  helm template ps "$CHART" "$@" 2>&1
}

# policy_docs — only the ClusterPolicy manifests this chart owns. Scoping by
# `# Source:` keeps the assertions honest if a subchart is ever reintroduced.
policy_docs() {
  awk '
    /^# Source: platform-security\/templates\/kyverno-policies\// { keep = 1; print; next }
    /^# Source: / { keep = 0 }
    keep { print }
  '
}

policy_count() {
  policy_docs <<<"$1" | grep -c '^kind: ClusterPolicy$'
}

@test "renders all six ClusterPolicies by default" {
  local out
  out="$(render)"
  [ "$(policy_count "$out")" -eq 6 ]
}

@test "every policy is present by name" {
  local out
  out="$(render | policy_docs)"
  for p in "${POLICIES[@]}"; do
    [[ "$out" == *"name: $p"* ]] || {
      echo "missing policy: $p"
      return 1
    }
  done
}

@test "defaults to Audit, never Enforce" {
  # The whole point of the 2026-08-05 rollout.
  local out
  out="$(render | policy_docs)"
  [ "$(grep -c 'validationFailureAction: Audit' <<<"$out")" -eq 6 ]
  [ "$(grep -c 'validationFailureAction: Enforce' <<<"$out")" -eq 0 ]
}

@test "validationFailureAction is overridable to Enforce" {
  # Audit is the default, not a ceiling — promoting a clean cluster must work.
  local out
  out="$(render --set kyvernoPolicies.validationFailureAction=Enforce | policy_docs)"
  [ "$(grep -c 'validationFailureAction: Enforce' <<<"$out")" -eq 6 ]
  [ "$(grep -c 'validationFailureAction: Audit' <<<"$out")" -eq 0 ]
}

@test "kyvernoPolicies.enabled=false removes the policies" {
  # The documented first-install path on a cluster with no Kyverno CRDs yet.
  local out
  out="$(render --set kyvernoPolicies.enabled=false)"
  [ "$(policy_count "$out")" -eq 0 ]
}

@test "policies are gated on the engine, not shipped without it" {
  # Rendering ClusterPolicies while kyverno.enabled=false would produce
  # manifests whose CRD is guaranteed absent — the install fails with
  # 'no matches for kind "ClusterPolicy"'.
  local out
  out="$(render --set kyverno.enabled=false)"
  [ "$(policy_count "$out")" -eq 0 ]
}

@test "every rendered policy declares a concrete failure action" {
  # A policy whose action templated to empty is accepted by the API server and
  # silently defaults. The count-of-6 guard first is deliberate: grep -c on an
  # empty render also returns 0, so without it a failed render would pass this
  # test — which is exactly how the previous version of this file reported a
  # green result while rendering nothing at all in CI.
  local out
  out="$(render | policy_docs)"
  [ "$(grep -c '^kind: ClusterPolicy$' <<<"$out")" -eq 6 ]
  [ "$(grep -c 'validationFailureAction:[[:space:]]*$' <<<"$out")" -eq 0 ]
}

@test "trivy-operator is off by default and its subchart is condition-gated" {
  # infra's platform-vendor ApplicationSet already installs the aquasecurity
  # chart into trivy-system; a second operator would reconcile the same
  # VulnerabilityReport CRDs. Asserted as a values+condition contract rather
  # than by rendering the subchart, which this file cannot do offline — the two
  # together are what guarantee it stays out of the render.
  grep -A1 '^trivy-operator:' "${CHART_SRC}/values.yaml" | grep -q 'enabled: false'
  awk '
    $1 == "-" && $2 == "name:" { dep = ($3 == "trivy-operator") }
    dep && $1 == "condition:"  { print $2; exit }
  ' "${CHART_SRC}/Chart.yaml" | grep -qx 'trivy-operator.enabled'
}
