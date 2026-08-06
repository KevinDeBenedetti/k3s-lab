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
# It also pins the two enable-gates that carry the same risk in reverse: a chart
# that silently renders *no* policy is the failure mode the audit actually found,
# and it looks identical to a healthy run unless something counts.
#
# All subcharts are vendored under charts/platform-security/charts/, so every
# render here is offline.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHART="${REPO_ROOT}/charts/platform-security"

POLICIES=(
  require-non-root
  require-ro-rootfs
  restrict-capabilities
  disallow-privilege-escalation
  disallow-latest-tag
  require-pod-resources
)

# render [--set k=v ...] — falco and tetragon are DaemonSets irrelevant to every
# assertion here and slow to template; they are off in all cases.
render() {
  helm template ps "$CHART" \
    --set falco.enabled=false \
    --set tetragon.enabled=false \
    "$@" 2>&1
}

# policy_docs — only the ClusterPolicy manifests this chart itself owns.
# Scoping by `# Source:` is load-bearing: the Kyverno subchart ships a
# `clusterpolicies.kyverno.io` CRD whose schema text contains both the literal
# `kind: ClusterPolicy` and the word `validationFailureAction`, so an unscoped
# grep counts the CRD as a policy and reports a pass with zero policies present.
policy_docs() {
  awk '
    /^# Source: platform-security\/templates\/kyverno-policies\// { keep = 1; print; next }
    /^# Source: / { keep = 0 }
    keep { print }
  '
}

@test "renders all six ClusterPolicies by default" {
  run bash -c "$(declare -f render policy_docs); CHART='$CHART'; render | policy_docs | grep -c '^kind: ClusterPolicy$'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 6 ]
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
  # The whole point of the 2026-08-05 rollout. Six policies, six Audit values,
  # and no Enforce anywhere in this chart's own manifests.
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

@test "kyvernoPolicies.enabled=false removes the policies but keeps the engine" {
  # The documented first-install path on a cluster with no Kyverno CRDs yet.
  local out
  out="$(render --set kyvernoPolicies.enabled=false)"
  [ "$(policy_docs <<<"$out" | grep -c '^kind: ClusterPolicy$')" -eq 0 ]
  # The engine must still be installed — otherwise the second step of the
  # rollout has nothing to enable against.
  [[ "$out" == *"name: kyverno-admission-controller"* ]]
}

@test "policies are gated on the engine, not shipped without it" {
  # Rendering ClusterPolicies while kyverno.enabled=false would produce
  # manifests whose CRD is guaranteed absent — the install fails with
  # 'no matches for kind "ClusterPolicy"'.
  local out
  out="$(render --set kyverno.enabled=false)"
  [ "$(policy_docs <<<"$out" | grep -c '^kind: ClusterPolicy$')" -eq 0 ]
}

@test "trivy-operator stays off — infra already provides it" {
  # Enabling it here too gives two operators reconciling the same
  # VulnerabilityReport CRDs (infra's platform-vendor ApplicationSet installs the
  # aquasecurity chart into trivy-system). The comment in values.yaml says so;
  # this asserts it.
  #
  # Counting the subchart's own `# Source:` attribution rather than grepping for
  # the string "trivy-operator": that string also appears in this chart's values
  # comments and in unrelated RBAC names, so a substring check would pass whether
  # the subchart rendered or not.
  local out
  out="$(render)"
  [ "$(grep -c '^# Source: platform-security/charts/trivy-operator/' <<<"$out")" -eq 0 ]
}

@test "the trivy-operator gate is real, not vacuously satisfied" {
  # Guards the test above: if the subchart could never render under any setting,
  # asserting its absence would prove nothing. Turning it on must produce
  # manifests — that is what makes the default-off assertion meaningful.
  local out
  out="$(render --set trivy-operator.enabled=true)"
  [ "$(grep -c '^# Source: platform-security/charts/trivy-operator/' <<<"$out")" -gt 0 ]
}

@test "every rendered policy declares a concrete failure action" {
  # A policy whose action templated to empty is accepted by the API server and
  # silently defaults — the exact class of bug this chart already had once.
  local out
  out="$(render | policy_docs)"
  [ "$(grep -c 'validationFailureAction:[[:space:]]*$' <<<"$out")" -eq 0 ]
}
