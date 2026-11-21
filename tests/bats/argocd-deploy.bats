#!/usr/bin/env bats
# tests/bats/argocd-deploy.bats — scripts/argocd-deploy.sh against
# tests/bats/helpers/fake-helm, on a machine with no Helm repositories
# registered (a fresh HELM_CONFIG_HOME). Regression test for #122: the deploy
# used `helm dependency build`, which fails until `helm repo add` has run.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/argocd-deploy.sh"

setup() {
  export HELM="${REPO_ROOT}/tests/bats/helpers/fake-helm"
  export HELM_CONFIG_HOME="${BATS_TEST_TMPDIR}/helm-config"   # empty: fresh machine
  export FAKE_HELM_LOG="${BATS_TEST_TMPDIR}/helm.log"
  export K3S_LAB_PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
  mkdir -p "$K3S_LAB_PROJECT_DIR"
  cd "$K3S_LAB_PROJECT_DIR"
  export KUBECONFIG_CONTEXT=lab ARGOCD_DOMAIN=argocd.example.test
  unset ARGOCD_VALUES_FILE K3S_LAB_ENV_FILE
}

@test "deploy works on a machine with no Helm repositories registered" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '^upgrade --install argocd .*charts/platform-argocd' "$FAKE_HELM_LOG"
}

@test "the upgrade targets the given context and domain" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--kube-context lab ' "$FAKE_HELM_LOG"
  grep -q -- 'argo-cd.global.domain=argocd.example.test' "$FAKE_HELM_LOG"
  grep -q -- 'argo-cd.configs.cm.url=https://argocd.example.test' "$FAKE_HELM_LOG"
}

@test "a values file is layered on when set" {
  printf 'argo-cd: {}\n' >"${K3S_LAB_PROJECT_DIR}/argocd.yaml"
  ARGOCD_VALUES_FILE=argocd.yaml run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--values argocd.yaml' "$FAKE_HELM_LOG"
}

@test "the values file can be given as an argument, as the task does" {
  printf 'argo-cd: {}\n' >"${K3S_LAB_PROJECT_DIR}/argocd.yaml"
  run "$SCRIPT" argocd.yaml
  [ "$status" -eq 0 ]
  grep -q -- '--values argocd.yaml' "$FAKE_HELM_LOG"
}

@test "an empty argument does not mask ARGOCD_VALUES_FILE from .env" {
  printf 'argo-cd: {}\n' >"${K3S_LAB_PROJECT_DIR}/from-env.yaml"
  printf 'ARGOCD_VALUES_FILE=from-env.yaml\n' >"${K3S_LAB_PROJECT_DIR}/.env"
  run "$SCRIPT" ""
  [ "$status" -eq 0 ]
  grep -q -- '--values from-env.yaml' "$FAKE_HELM_LOG"
}

@test "a missing values file stops before Helm runs" {
  ARGOCD_VALUES_FILE=nope.yaml run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ARGOCD_VALUES_FILE not found"* ]]
  [ ! -s "$FAKE_HELM_LOG" ]
}

@test "KUBECONFIG_CONTEXT and ARGOCD_DOMAIN are required" {
  unset KUBECONFIG_CONTEXT
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"KUBECONFIG_CONTEXT"* ]]
  [ ! -s "$FAKE_HELM_LOG" ]
}
