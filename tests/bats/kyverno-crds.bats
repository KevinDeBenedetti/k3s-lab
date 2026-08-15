#!/usr/bin/env bats
# tests/bats/kyverno-crds.bats — Tests for scripts/check-kyverno-crds.sh
#
# The script under test is the only check in this repo that needs a cluster, so
# these tests stub `kubectl` through the KUBECTL injection point. The stub is a
# real script on PATH-free absolute path, driven by files in BATS_TEST_TMPDIR —
# that keeps every case declarative: write the CRD table the cluster would
# return, list the objects it holds, run.
#
# What is worth testing here is the shape of the failures, not the happy path:
# a missing CRD, a CRD that exists but no longer serves the rendered apiVersion,
# and a policy that is installable yet absent — the last being the one that sat
# undetected for 32h behind an OutOfSync/Healthy Application.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-kyverno-crds.sh"

setup() {
  CHART="${BATS_TEST_TMPDIR}/chart"
  mkdir -p "${CHART}/templates/kyverno-policies"
  cat > "${CHART}/Chart.yaml" <<'EOF'
apiVersion: v2
name: platform-security
version: 0.1.0
EOF
  cat > "${CHART}/values.yaml" <<'EOF'
kyverno:
  enabled: true
kyvernoPolicies:
  enabled: true
EOF
  cat > "${CHART}/templates/kyverno-policies/policies.yaml" <<'EOF'
{{- if and .Values.kyverno.enabled .Values.kyvernoPolicies.enabled }}
{{- range $name := list "require-non-root" "disallow-latest-tag" }}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ $name }}
spec:
  rules: []
{{- end }}
{{- end }}
EOF

  # The cluster, as two files the stub reads.
  CRD_TABLE="${BATS_TEST_TMPDIR}/crds.tsv"
  OBJECTS="${BATS_TEST_TMPDIR}/objects.txt"
  printf 'kyverno.io\tClusterPolicy\tclusterpolicies\tv1,\n' > "$CRD_TABLE"
  printf 'clusterpolicies.kyverno.io/require-non-root\nclusterpolicies.kyverno.io/disallow-latest-tag\n' > "$OBJECTS"

  STUB="${BATS_TEST_TMPDIR}/kubectl"
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
# $1 = get; $2 = crd -> emit the table. Otherwise: `get <plural.group> <name>`.
if [ "$2" = "crd" ]; then
  cat "$CRD_TABLE"
  exit 0
fi
grep -qx "$2/$3" "$OBJECTS"
EOF
  chmod +x "$STUB"
  export CRD_TABLE OBJECTS
}

run_check() {
  KUBECTL="$STUB" run "$SCRIPT" --chart "$CHART" "$@"
}

@test "passes when the CRD is present and every policy landed" {
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"CRD present and serving v1"* ]]
  [[ "$output" == *"all 2 rendered policy(ies) exist"* ]]
}

@test "fails when the CRD backing a rendered policy does not exist" {
  # The first-install hazard: enabling the policies before the engine.
  : > "$CRD_TABLE"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no CRD for it in this cluster"* ]]
  [[ "$output" == *'no matches for kind "ClusterPolicy"'* ]]
}

@test "fails when the CRD exists but no longer serves the rendered version" {
  # A present CRD is not enough — this is the shape a Kyverno major takes, and
  # it fails at the same point with a message that reads like a missing CRD.
  printf 'kyverno.io\tClusterPolicy\tclusterpolicies\tv2,\n' > "$CRD_TABLE"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not serve v1"* ]]
  [[ "$output" == *"served: v2"* ]]
}

@test "fails when a policy is installable but absent from the cluster" {
  # The 2026-08-13 case: the AppProject refused the kind, so the Application was
  # OutOfSync/Healthy and `kubectl get clusterpolicy` returned nothing, while the
  # CRD itself was present the whole time.
  : > "$OBJECTS"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"renders, is installable, and is NOT in the cluster"* ]]
  [[ "$output" == *"clusterResourceWhitelist"* ]]
}

@test "reports every missing policy, not just the first" {
  : > "$OBJECTS"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"require-non-root"* ]]
  [[ "$output" == *"disallow-latest-tag"* ]]
  [[ "$output" == *"2 problem(s)"* ]]
}

@test "--crds-only ignores whether the policies landed" {
  : > "$OBJECTS"
  run_check --crds-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"All 1 Kyverno CRD(s)"* ]]
  [[ "$output" != *"NOT in the cluster"* ]]
}

@test "a chart that renders no policy asserts nothing and says so" {
  cat > "${CHART}/values.yaml" <<'EOF'
kyverno:
  enabled: true
kyvernoPolicies:
  enabled: false
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to install, nothing to check"* ]]
}

@test "the engine being disabled also renders nothing" {
  cat > "${CHART}/values.yaml" <<'EOF'
kyverno:
  enabled: false
kyvernoPolicies:
  enabled: true
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to install, nothing to check"* ]]
}

@test "one CRD is reported once, not once per policy sharing it" {
  # Six policies share one ClusterPolicy CRD; asserting per policy would print
  # the same missing-CRD error six times and inflate the error count.
  : > "$CRD_TABLE"
  run_check
  [ "$status" -eq 1 ]
  [ "$(grep -c 'no CRD for it in this cluster' <<<"$output")" -eq 1 ]
  [[ "$output" == *"1 problem(s)"* ]]
}

@test "an unreachable cluster is an error, not an empty pass" {
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
echo "Unable to connect to the server: dial tcp: i/o timeout" >&2
exit 1
EOF
  chmod +x "$STUB"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot list CustomResourceDefinitions"* ]]
}

@test "a values overlay can turn the policies off" {
  # How infra's own values file would be passed in.
  cat > "${BATS_TEST_TMPDIR}/override.yaml" <<'EOF'
kyvernoPolicies:
  enabled: false
EOF
  run_check --values "${BATS_TEST_TMPDIR}/override.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to install, nothing to check"* ]]
}

@test "a parse failure is refused rather than reported as nothing to check" {
  # The guard on the extractor. Simulated by rendering a kyverno-policies
  # document whose body the awk cannot attribute — the `# Source:` line is
  # present, so "no policy parsed" must be a bug, not a clean cluster.
  cat > "${CHART}/templates/kyverno-policies/policies.yaml" <<'EOF'
# intentionally emits a document with no apiVersion/kind/name triple
{{- if .Values.kyverno.enabled }}
---
spec:
  rules: []
{{- end }}
EOF
  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing to report success"* ]]
}
