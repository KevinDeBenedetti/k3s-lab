#!/usr/bin/env bats
# tests/bats/platform-security-render.bats — Render contract for charts/platform-security
#
# Why this file exists: until 2026-08-05 this chart shipped six Kyverno
# ClusterPolicies hardcoded to `Enforce` and was
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

# Six policies, seven rules: `disallow-latest-tag` carries two
# (require-image-tag + require-tag-or-digest). Since 2026-08-14 the failure
# action is set per rule rather than once per policy, so every action assertion
# counts RULES, not policies — a 6 here would pass while one rule silently lost
# its action.
RULE_COUNT=7

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
  [ "$(grep -c 'failureAction: Audit' <<<"$out")" -eq "$RULE_COUNT" ]
  [ "$(grep -c 'failureAction: Enforce' <<<"$out")" -eq 0 ]
}

@test "failureAction is overridable to Enforce" {
  # Audit is the default, not a ceiling — promoting a clean cluster must work.
  local out
  out="$(render --set kyvernoPolicies.failureAction=Enforce | policy_docs)"
  [ "$(grep -c 'failureAction: Enforce' <<<"$out")" -eq "$RULE_COUNT" ]
  [ "$(grep -c 'failureAction: Audit' <<<"$out")" -eq 0 ]
}

@test "the deprecated validationFailureAction value key still overrides" {
  # infra pins this chart and sets the old key (platform/security/values.yaml).
  # Helm ignores unknown value keys silently, so dropping the alias would not
  # error — it would quietly revert that install to the chart default. This test
  # is what makes removing the alias a visible decision rather than an accident.
  local out
  out="$(render --set kyvernoPolicies.validationFailureAction=Enforce | policy_docs)"
  [ "$(grep -c 'failureAction: Enforce' <<<"$out")" -eq "$RULE_COUNT" ]
  [ "$(grep -c 'failureAction: Audit' <<<"$out")" -eq 0 ]
}

@test "the new key wins over the deprecated alias" {
  local out
  out="$(render \
    --set kyvernoPolicies.failureAction=Enforce \
    --set kyvernoPolicies.validationFailureAction=Audit | policy_docs)"
  [ "$(grep -c 'failureAction: Enforce' <<<"$out")" -eq "$RULE_COUNT" ]
}

@test "the action is set per rule, not with the deprecated spec-level field" {
  # Kyverno 3.8 marks spec.validationFailureAction "Deprecated, use
  # validationFailureAction under the validate rule instead" in the ClusterPolicy
  # CRD. It still works, so nothing in the cluster would report a regression —
  # only this test would.
  local out
  out="$(render | policy_docs)"
  # The spec-level field is a top-level key of spec:, i.e. two-space indented.
  [ "$(grep -c '^  validationFailureAction:' <<<"$out")" -eq 0 ]
  # …and every occurrence of the new one sits inside a validate: block.
  [ "$(grep -c '^        failureAction:' <<<"$out")" -eq "$RULE_COUNT" ]
}

@test "an invalid failure action fails the render" {
  # An empty or bogus action is accepted by the API server and silently defaults,
  # so the helper calls `fail`. Without this, a typo would reach the cluster.
  run render --set kyvernoPolicies.failureAction=audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be Audit or Enforce"* ]]
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
  [ "$(grep -c 'failureAction:[[:space:]]*$' <<<"$out")" -eq 0 ]
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

# ─── Namespace exclusions ───────────────────────────────────────────────────
# The six policies carry DIFFERENT exclusion lists (2 to 8 namespaces), tailored
# to what each one actually has to let through. They are not six copies of one
# list, and the tempting "let's factor this out" refactor would widen five of
# them at once — silently, since a wider exclusion never fails a render.
#
# `ci` (the ARC runner namespace) was added on 2026-08-19 to exactly the two
# policies those pods violate, replacing infra's PolicyException. These tests
# pin both halves: that it IS excluded where it must be, and that it is NOT
# excluded anywhere else.

# ns_for POLICY <<< render — the namespaces a policy's first rule excludes
ns_for() {
  policy_docs | awk -v want="$1" '
    /^kind: ClusterPolicy$/ { inpol = 0 }
    $1 == "name:" && $2 == want && !seen { inpol = 1; seen = 1; next }
    inpol && /namespaces:/ { grab = 1; next }
    grab && /^[[:space:]]*#/ { next }
    grab && /^[[:space:]]*$/ { next }
    grab && /^[[:space:]]*-[[:space:]]/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
    grab { grab = 0 }
  '
}

@test "the ci namespace is excluded from require-ro-rootfs" {
  run render --set kyverno.enabled=true --set kyvernoPolicies.enabled=true
  [ "$status" -eq 0 ]
  ns="$(ns_for require-ro-rootfs <<<"$output")"
  [[ "$ns" == *"ci"* ]]
}

@test "the ci namespace is excluded from restrict-capabilities" {
  run render --set kyverno.enabled=true --set kyvernoPolicies.enabled=true
  [ "$status" -eq 0 ]
  ns="$(ns_for restrict-capabilities <<<"$output")"
  [[ "$ns" == *"ci"* ]]
}

@test "the ci exemption does NOT leak into the other four policies" {
  run render --set kyverno.enabled=true --set kyvernoPolicies.enabled=true
  [ "$status" -eq 0 ]
  for policy in require-non-root require-pod-resources \
                disallow-privilege-escalation disallow-latest-tag; do
    ns="$(ns_for "$policy" <<<"$output")"
    if grep -qx 'ci' <<<"$ns"; then
      echo "FAIL: '$policy' excludes ci; only require-ro-rootfs and"
      echo "      restrict-capabilities should. The ARC runners violate those two"
      echo "      and nothing else — a wider exemption is a security regression"
      echo "      that no render will complain about."
      return 1
    fi
  done
}

@test "the exclusion lists stay distinct, not unified into one" {
  run render --set kyverno.enabled=true --set kyvernoPolicies.enabled=true
  [ "$status" -eq 0 ]
  a="$(ns_for disallow-privilege-escalation <<<"$output" | sort | tr '\n' ' ')"
  b="$(ns_for require-ro-rootfs <<<"$output" | sort | tr '\n' ' ')"
  # If these ever become equal, someone factored the lists together and
  # disallow-privilege-escalation just gained five exemptions it never had.
  [ "$a" != "$b" ]
}
