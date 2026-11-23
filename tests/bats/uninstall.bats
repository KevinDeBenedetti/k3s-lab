#!/usr/bin/env bats
# tests/bats/uninstall.bats — scripts/uninstall.sh against a fake kubectl (the
# K seam) and a fake helm (the HELM seam). The script is the destructive end of
# the toolkit: it must say plainly when it could not remove something, instead
# of printing "Infrastructure removed" over every failure (#125).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/uninstall.sh"

setup() {
  BIN="${BATS_TEST_TMPDIR}/bin"
  export CALLS="${BATS_TEST_TMPDIR}/calls" STATE="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$BIN" "$STATE"
  # Fake cluster: releases are files state/releases/<ns>/<name>; namespaces
  # state/ns/<name>. FAKE_UNREACHABLE, FAKE_HELM_FAIL=<release>,
  # FAKE_NS_FAIL=<ns> inject failures.
  cat >"${BIN}/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >>"$CALLS"
[[ "$1" == --context ]] && shift 2
case "$1" in
  cluster-info) [[ -z "${FAKE_UNREACHABLE:-}" ]] || { echo "Unable to connect to the server" >&2; exit 1; } ;;
  delete)
    ns="$3"
    [[ "$ns" != "${FAKE_NS_FAIL:-}" ]] || { echo "Error from server (Forbidden)" >&2; exit 1; }
    rm -rf "$STATE/ns/$ns" "$STATE/releases/$ns" ;;
  *) echo "fake kubectl: unexpected $*" >&2; exit 64 ;;
esac
SH
  cat >"${BIN}/helm" <<'SH'
#!/usr/bin/env bash
echo "helm $*" >>"$CALLS"
ns=""; args=()
while [[ $# -gt 0 ]]; do
  case "$1" in -n) ns="$2"; shift 2 ;; --kube-context) shift 2 ;; *) args+=("$1"); shift ;; esac
done
case "${args[0]}" in
  list) ls "$STATE/releases/$ns" 2>/dev/null || true ;;
  uninstall)
    r="${args[1]}"
    [[ "$r" != "${FAKE_HELM_FAIL:-}" ]] || { echo "Error: uninstall: timed out" >&2; exit 1; }
    [[ -e "$STATE/releases/$ns/$r" ]] || { echo "Error: uninstall: Release not loaded: $r: release: not found" >&2; exit 1; }
    rm -f "$STATE/releases/$ns/$r" ;;
  *) echo "fake helm: unexpected ${args[*]}" >&2; exit 64 ;;
esac
SH
  chmod +x "${BIN}/kubectl" "${BIN}/helm"
  export K="${BIN}/kubectl --context lab" HELM="${BIN}/helm"
  export KUBECONFIG_CONTEXT=lab UNINSTALL_GRACE_SECONDS=0
  export K3S_LAB_PROJECT_DIR="${BATS_TEST_TMPDIR}"
  cd "$BATS_TEST_TMPDIR"
  unset HELM_RELEASES NAMESPACES
}

release() { mkdir -p "$STATE/releases/$2" "$STATE/ns/$2"; touch "$STATE/releases/$2/$1"; }

@test "an unreachable cluster stops before anything is attempted" {
  FAKE_UNREACHABLE=1 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot reach"* ]]
  ! grep -q '^helm ' "$CALLS" || { echo "helm was called"; return 1; }
}

@test "every release found in a target namespace is uninstalled, whatever its name" {
  release platform-vault vault
  release security security
  release my-argo argocd
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$STATE/releases" 2>/dev/null)" ]
  grep -q 'helm uninstall platform-vault -n vault' "$CALLS"
  grep -q 'helm uninstall security -n security' "$CALLS"
  [[ "$output" == *"Infrastructure removed"* ]]
}

@test "the default namespaces cover platform-base's and security" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # The source of truth is the chart, not a copy of the script's list.
  for ns in $(yq -r '.namespaces[].name' "${REPO_ROOT}/charts/platform-base/values.yaml") security argocd; do
    grep -q "^kubectl --context lab delete namespace ${ns} " "$CALLS" || { echo "namespace $ns not deleted"; return 1; }
  done
}

@test "a release that fails to uninstall makes the run fail, and is named" {
  release traefik ingress
  release cert-manager cert-manager
  FAKE_HELM_FAIL=traefik run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"traefik"* ]]
  [[ "$output" != *"Infrastructure removed"* ]]
  # the others are still attempted
  grep -q 'helm uninstall cert-manager -n cert-manager' "$CALLS"
}

@test "a namespace that fails to delete makes the run fail, and is named" {
  FAKE_NS_FAIL=vault run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vault"* ]]
  [[ "$output" != *"Infrastructure removed"* ]]
}

@test "HELM_RELEASES still overrides the discovery, and a missing release is not an error" {
  release traefik ingress
  HELM_RELEASES=$'traefik ingress\nghost ghost-ns' NAMESPACES="ingress" run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'helm uninstall traefik -n ingress' "$CALLS"
  ! grep -q 'helm list' "$CALLS" || { echo "discovery ran despite HELM_RELEASES"; return 1; }
}
