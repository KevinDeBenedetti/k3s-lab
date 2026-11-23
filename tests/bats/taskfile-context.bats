#!/usr/bin/env bats
# tests/bats/taskfile-context.bats — how the taskfiles name the kube context.
#
# Until #131 they called `kubectl --context $KUBECONFIG_CONTEXT` 23 times,
# unquoted and with no default: with the variable unset the command became
# `kubectl --context get nodes`, which reads `get` as the context name, while
# the scripts default the same variable to k3s-lab. Each taskfile now defines
# it once, as a Task var with that default, and quotes it. Task is not on the
# CI runner, so this reads the files.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

@test "no taskfile passes the context as an unquoted shell variable" {
  run grep -n -E -- '--(kube-)?context \$' "${REPO_ROOT}"/taskfiles/*.yml
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "every taskfile that names the context defines it, with the scripts' default" {
  for f in "${REPO_ROOT}"/taskfiles/*.yml; do
    grep -q -- '--context' "$f" || continue
    grep -q "^  KUBECONFIG_CONTEXT: '{{.KUBECONFIG_CONTEXT | default \"k3s-lab\"}}'$" "$f" \
      || { echo "$(basename "$f"): no KUBECONFIG_CONTEXT var with the k3s-lab default"; return 1; }
  done
}

@test "every --context in the taskfiles reads that var, quoted" {
  bad="$(grep -h -o -E -- '--context [^ ]+' "${REPO_ROOT}"/taskfiles/*.yml | grep -v -F -- '--context "{{.KUBECONFIG_CONTEXT}}"' || true)"
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}
