#!/usr/bin/env bats
# tests/bats/kustomize-components.bats — every kubernetes/components/* built
# the way docs/kustomize-components.md uses it: listed under `components:` of
# an app overlay. Nothing else builds them (kubeconform skips
# kustomization.yaml), which is how all six shipped unusable (#124).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  if command -v kustomize >/dev/null 2>&1; then
    KUSTOMIZE=(kustomize build)
  elif command -v kubectl >/dev/null 2>&1; then
    KUSTOMIZE=(kubectl kustomize)
  elif [[ -n "${CI:-}" ]]; then
    echo "neither kustomize nor kubectl on the CI runner" >&2
    return 1
  else
    skip "needs kustomize or kubectl"
  fi
  # kustomize refuses absolute component paths: lay out a copy of the
  # repository next to the app, as a config repo vendoring k3s-lab would.
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}/k3s-lab" "${WORK}/app"
  cp -R "${REPO_ROOT}/kubernetes" "${WORK}/k3s-lab/"
  cat >"${WORK}/app/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  selector:
    matchLabels: {app: myapp}
  template:
    metadata:
      labels: {app: myapp}
    spec:
      containers:
        - name: web
          image: nginx:1.27
YAML
}

# overlay <component>… — an app kustomization using the given components.
overlay() {
  {
    printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nnamespace: myapp\n'
    printf 'resources:\n  - deployment.yaml\ncomponents:\n'
    local c
    for c in "$@"; do printf '  - ../k3s-lab/kubernetes/components/%s\n' "$c"; done
  } >"${WORK}/app/kustomization.yaml"
}

build() { "${KUSTOMIZE[@]}" "${WORK}/app"; }

@test "every component builds when listed under components:" {
  for dir in "${REPO_ROOT}"/kubernetes/components/*/; do
    c="$(basename "$dir")"
    overlay "$c"
    run build
    [ "$status" -eq 0 ] || { echo "$c: $output"; return 1; }
  done
}

@test "app-base hardens the app's own container, whatever it is named" {
  overlay app-base
  run build
  [ "$status" -eq 0 ]
  sc="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[0].securityContext' <<<"$output")"
  [ "$(yq -r '.allowPrivilegeEscalation' <<<"$sc")" = "false" ]
  [ "$(yq -r '.readOnlyRootFilesystem' <<<"$sc")" = "true" ]
  [ "$(yq -r '.runAsNonRoot' <<<"$sc")" = "true" ]
  [ "$(yq -r '.capabilities.drop[0]' <<<"$sc")" = "ALL" ]
  [ "$(yq -r '.seccompProfile.type' <<<"$sc")" = "RuntimeDefault" ]
  # no second container was injected beside the app's own
  [ "$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers | length' <<<"$output")" = "1" ]
}

@test "app-base does not mount a service-account token by default" {
  overlay app-base
  run build
  [ "$status" -eq 0 ]
  [ "$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.automountServiceAccountToken' <<<"$output")" = "false" ]
  [ "$(yq -r 'select(.kind == "ServiceAccount") | .automountServiceAccountToken' <<<"$output")" = "false" ]
}

@test "network-policies select namespaces by the label Kubernetes sets" {
  overlay network-policies
  run build
  [ "$status" -eq 0 ]
  # `name:` is not set on namespaces by Kubernetes; kubernetes.io/metadata.name is.
  bare="$(yq '.. | select(tag == "!!map") | select(has("namespaceSelector")) | .namespaceSelector.matchLabels.name | select(. != null)' <<<"$output" | grep -v '^---' || true)"
  [ -z "$bare" ] || { echo "bare name: selectors: $bare"; return 1; }
  dns="$(yq 'select(.metadata.name == "allow-dns-egress") | .spec.egress[].to[].namespaceSelector.matchLabels."kubernetes.io/metadata.name" | select(. != null)' <<<"$output")"
  [[ "$dns" == *kube-system* ]]
  ing="$(yq 'select(.metadata.name == "allow-from-ingress-controller") | .spec.ingress[].from[].namespaceSelector.matchLabels."kubernetes.io/metadata.name" | select(. != null)' <<<"$output")"
  [[ "$ing" == *ingress* ]]
}

@test "an app's own patch runs after app-base and can set runAsUser" {
  overlay app-base
  cat >>"${WORK}/app/kustomization.yaml" <<'YAML'
patches:
  - target: {kind: Deployment, name: myapp}
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/securityContext/runAsUser
        value: 1000
YAML
  run build
  [ "$status" -eq 0 ]
  sc="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[0].securityContext' <<<"$output")"
  [ "$(yq -r '.runAsUser' <<<"$sc")" = "1000" ]
  [ "$(yq -r '.readOnlyRootFilesystem' <<<"$sc")" = "true" ]
}
