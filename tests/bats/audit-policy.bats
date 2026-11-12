#!/usr/bin/env bats
# tests/bats/audit-policy.bats — ansible/roles/k3s_server/files/audit-policy.yaml
#
# The API server refuses to START on an invalid policy, and there is no schema
# for audit.k8s.io/v1 in kubeconform's catalogue. These checks cover the rules
# the API server enforces when it loads the file, plus the one property the
# policy exists for: Secret bodies are never logged.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
POLICY="${REPO_ROOT}/ansible/roles/k3s_server/files/audit-policy.yaml"

@test "the policy is an audit.k8s.io/v1 Policy" {
  [ "$(yq -r '.apiVersion' "$POLICY")" = "audit.k8s.io/v1" ]
  [ "$(yq -r '.kind' "$POLICY")" = "Policy" ]
}

@test "every rule has a valid level" {
  bad="$(yq -r '.rules[].level | select(. != "None" and . != "Metadata" and . != "Request" and . != "RequestResponse")' "$POLICY")"
  [ -z "$bad" ] || { echo "invalid level(s): $bad"; return 1; }
}

@test "no rule mixes nonResourceURLs with resources or namespaces" {
  n="$(yq -r '[.rules[] | select(has("nonResourceURLs") and (has("resources") or has("namespaces")))] | length' "$POLICY")"
  [ "$n" -eq 0 ]
}

@test "nonResourceURLs only use a trailing wildcard" {
  bad="$(yq -r '.rules[].nonResourceURLs[]? | select(test("\\*.") or (test("^/") | not))' "$POLICY")"
  [ -z "$bad" ] || { echo "invalid URL pattern(s): $bad"; return 1; }
}

@test "the last rule is a catch-all" {
  [ "$(yq -r '.rules[-1] | keys | join(",")' "$POLICY")" = "level" ]
}

@test "secrets are logged at Metadata, never with their body" {
  # The first rule naming secrets decides; it must not be Request/RequestResponse.
  level="$(yq -r '[.rules[] | select(.resources[]?.resources[]? == "secrets")][0].level' "$POLICY")"
  [ "$level" = "Metadata" ]
  # And no rule may log bodies for every resource of the core group.
  n="$(yq -r '[.rules[] | select(.level == "Request" or .level == "RequestResponse") | .resources[]? | select(.group == "" and (has("resources") | not))] | length' "$POLICY")"
  [ "$n" -eq 0 ]
}
