#!/usr/bin/env bats
# lima.bats — offline validation of Lima smoke-test manifests and VM configs
#
# What these tests cover:
#   ✅ Lima VM config files exist and are consistent (port forwards)
#   ✅ Smoke YAML manifests exist and contain all required Kubernetes resources
#   ✅ Both smoke pipelines mirror the production cert-manager → Traefik pattern
#   ✅ Makefile exposes every required Lima target
#
# Integration tests (require a running Lima k3s cluster):
#   — Automatically skipped when `kubectl --context k3s-lima` is not reachable
#   ✅ whoami app responds HTTP 200 via TLS (smoke-test.yaml pipeline)
#   ✅ Grafana /api/health responds HTTP 200 via TLS (smoke-monitoring.yaml pipeline)
#
# Run (offline only):
#   bats tests/bats/lima.bats
# Run (integration, Lima k3s must already be deployed via make vm-k3s-deploy):
#   bats tests/bats/lima.bats  # integration tests auto-run if cluster is reachable

setup() {
    load 'common-setup'
    _common_setup
    LIMA_DIR="$REPO_ROOT/tests/lima"
}

# ── Lima config files ─────────────────────────────────────────────────────────

@test "tests/lima/k3s-server.yaml exists" {
    [ -f "$LIMA_DIR/k3s-server.yaml" ]
}

@test "tests/lima/debian-vps.yaml exists" {
    [ -f "$LIMA_DIR/debian-vps.yaml" ]
}

@test "tests/lima/smoke-test.yaml exists" {
    [ -f "$LIMA_DIR/smoke-test.yaml" ]
}

@test "tests/lima/smoke-monitoring.yaml exists" {
    [ -f "$LIMA_DIR/smoke-monitoring.yaml" ]
}

# ── k3s-server.yaml port forwards ─────────────────────────────────────────────

@test "k3s-server.yaml forwards API server port 6443 to localhost" {
    grep -q "guestPort: 6443" "$LIMA_DIR/k3s-server.yaml"
    grep -q "hostPort: 6443"  "$LIMA_DIR/k3s-server.yaml"
}

@test "k3s-server.yaml forwards HTTPS NodePort 30443 → host 8443" {
    grep -q "guestPort: 30443" "$LIMA_DIR/k3s-server.yaml"
    grep -q "hostPort: 8443"   "$LIMA_DIR/k3s-server.yaml"
}

@test "k3s-server.yaml forwards HTTP NodePort 30080 → host 8080" {
    grep -q "guestPort: 30080" "$LIMA_DIR/k3s-server.yaml"
    grep -q "hostPort: 8080"   "$LIMA_DIR/k3s-server.yaml"
}

# ── smoke-test.yaml — whoami TLS pipeline ────────────────────────────────────

@test "smoke-test.yaml has ClusterIssuer" {
    grep -q "kind: ClusterIssuer" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml has Certificate" {
    grep -q "kind: Certificate" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml has Deployment" {
    grep -q "kind: Deployment" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml has Service" {
    grep -q "kind: Service" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml has IngressRoute" {
    grep -q "kind: IngressRoute" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml uses selfsigned-issuer (not letsencrypt — Lima has no public ingress)" {
    # Confirm the issuerRef points to selfsigned-issuer
    grep -q "name: selfsigned-issuer" "$LIMA_DIR/smoke-test.yaml"
    # The ClusterIssuer kind must be selfSigned, not acme
    grep -q "selfSigned: {}" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml routes on whoami.local" {
    grep -q "whoami.local" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml IngressRoute uses websecure entrypoint" {
    grep -q "websecure" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml whoami container has readinessProbe" {
    grep -q "readinessProbe" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml whoami Deployment is in apps namespace" {
    grep -q "namespace: apps" "$LIMA_DIR/smoke-test.yaml"
}

@test "smoke-test.yaml Certificate secretName matches IngressRoute tls.secretName" {
    secret="$(grep "secretName:" "$LIMA_DIR/smoke-test.yaml" | awk '{print $2}' | sort -u)"
    # All secretName entries in the file should resolve to the same name
    [ "$(echo "$secret" | wc -l | tr -d ' ')" -eq 1 ]
}

# ── smoke-monitoring.yaml — Grafana TLS pipeline ─────────────────────────────

@test "smoke-monitoring.yaml has ClusterIssuer" {
    grep -q "kind: ClusterIssuer" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml has Certificate" {
    grep -q "kind: Certificate" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml has Deployment" {
    grep -q "kind: Deployment" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml has Service" {
    grep -q "kind: Service" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml has IngressRoute" {
    grep -q "kind: IngressRoute" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml uses selfsigned-issuer (not letsencrypt)" {
    grep -q "name: selfsigned-issuer" "$LIMA_DIR/smoke-monitoring.yaml"
    ! grep -qi "letsencrypt" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml routes on grafana.local" {
    grep -q "grafana.local" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml IngressRoute uses websecure entrypoint" {
    grep -q "websecure" "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml grafana container has readinessProbe on /api/health" {
    grep -q "readinessProbe"  "$LIMA_DIR/smoke-monitoring.yaml"
    grep -q "/api/health"     "$LIMA_DIR/smoke-monitoring.yaml"
}

@test "smoke-monitoring.yaml Deployment is in monitoring namespace" {
    grep -q "namespace: monitoring" "$LIMA_DIR/smoke-monitoring.yaml"
}

# ── Make targets (Lima) ───────────────────────────────────────────────────────

_make_has_target() {
    local target="$1"
    make -C "$REPO_ROOT" -qp | grep -q "^${target}:"
}

@test "make exposes vm-k3s-create target" {
    _make_has_target "vm-k3s-create"
}

@test "make exposes vm-k3s-install target" {
    _make_has_target "vm-k3s-install"
}

@test "make exposes vm-k3s-kubeconfig target" {
    _make_has_target "vm-k3s-kubeconfig"
}

@test "make exposes vm-k3s-deploy target" {
    _make_has_target "vm-k3s-deploy"
}

@test "make exposes vm-k3s-deploy-monitoring target" {
    _make_has_target "vm-k3s-deploy-monitoring"
}

@test "tests/lima/grafana-cert.yaml exists" {
    [ -f "$LIMA_DIR/grafana-cert.yaml" ]
}

@test "grafana-cert.yaml has Certificate targeting grafana-tls secret" {
    grep -q "kind: Certificate"     "$LIMA_DIR/grafana-cert.yaml"
    grep -q "secretName: grafana-tls" "$LIMA_DIR/grafana-cert.yaml"
    grep -q "grafana.local"          "$LIMA_DIR/grafana-cert.yaml"
    grep -q "selfSigned: {}"         "$LIMA_DIR/grafana-cert.yaml"
}

# ── Make targets (Lima smoke) ────────────────────────────────────────────────

@test "make exposes vm-k3s-smoke target" {
    _make_has_target "vm-k3s-smoke"
}

@test "make exposes vm-k3s-smoke-monitoring target" {
    _make_has_target "vm-k3s-smoke-monitoring"
}

@test "make exposes vm-k3s-smoke-all target" {
    _make_has_target "vm-k3s-smoke-all"
}

@test "make exposes vm-k3s-full target" {
    _make_has_target "vm-k3s-full"
}

@test "make exposes vm-k3s-clean target" {
    _make_has_target "vm-k3s-clean"
}

# ── Integration tests — skip when Lima k3s cluster is not reachable ───────────
# Prerequisite: make vm-k3s-full && make vm-k3s-deploy

_k3s_lima_available() {
    command -v kubectl >/dev/null 2>&1 \
        && kubectl --context k3s-lima cluster-info --request-timeout=5s >/dev/null 2>&1
}

@test "[integration] k3s-lima context is reachable" {
    if ! _k3s_lima_available; then
        skip "k3s-lima context not reachable — run: make vm-k3s-full && make vm-k3s-deploy"
    fi
    run kubectl --context k3s-lima get nodes
    [ "$status" -eq 0 ]
}

@test "[integration] k3s-lima node is Ready" {
    if ! _k3s_lima_available; then
        skip "k3s-lima context not reachable"
    fi
    run bash -c "kubectl --context k3s-lima get nodes --no-headers | awk '{print \$2}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ready"* ]]
}

@test "[integration] traefik pod is Running in ingress namespace" {
    if ! _k3s_lima_available; then
        skip "k3s-lima context not reachable"
    fi
    run bash -c "kubectl --context k3s-lima get pods -n ingress --no-headers 2>/dev/null \
        | grep traefik | awk '{print \$3}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Running"* ]]
}

@test "[integration] cert-manager pod is Running" {
    if ! _k3s_lima_available; then
        skip "k3s-lima context not reachable"
    fi
    run bash -c "kubectl --context k3s-lima get pods -n cert-manager --no-headers 2>/dev/null \
        | grep 'cert-manager' | grep -v 'cainjector\|webhook' | awk '{print \$3}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Running"* ]]
}

@test "[integration] whoami app responds HTTP 200 via TLS (smoke-test pipeline)" {
    if ! _k3s_lima_available; then
        skip "k3s-lima context not reachable"
    fi

    # Apply smoke resources and wait for readiness
    kubectl --context k3s-lima apply -f "$LIMA_DIR/smoke-test.yaml" >/dev/null 2>&1
    kubectl --context k3s-lima rollout status deployment/whoami -n apps --timeout=60s >/dev/null 2>&1
    kubectl --context k3s-lima wait certificate whoami-tls -n apps \
        --for=condition=Ready --timeout=60s >/dev/null 2>&1

    # Retry up to 6×5s (30s) for Traefik to register backend endpoints
    local status
    for i in 1 2 3 4 5 6; do
        status="$(curl -sk --resolve 'whoami.local:8443:127.0.0.1' \
            https://whoami.local:8443/ -w '%{http_code}' -o /dev/null 2>/dev/null)"
        [ "$status" = "200" ] && break
        sleep 5
    done
    run echo "$status"
    [ "$output" = "200" ]

    # Cleanup
    kubectl --context k3s-lima delete -f "$LIMA_DIR/smoke-test.yaml" --ignore-not-found >/dev/null 2>&1
}

@test "[integration] grafana /api/health responds HTTP 200 via TLS (smoke-monitoring pipeline)" {
    if ! _k3s_lima_available; then
        skip "k3s-lima context not reachable"
    fi

    # Apply monitoring smoke resources and wait for readiness
    kubectl --context k3s-lima apply -f "$LIMA_DIR/smoke-monitoring.yaml" >/dev/null 2>&1
    kubectl --context k3s-lima rollout status deployment/grafana-smoke -n monitoring --timeout=120s >/dev/null 2>&1
    kubectl --context k3s-lima wait certificate grafana-smoke-tls -n monitoring \
        --for=condition=Ready --timeout=60s >/dev/null 2>&1

    # Retry up to 6×5s (30s) for Traefik to register backend endpoints
    local status
    for i in 1 2 3 4 5 6; do
        status="$(curl -sk --resolve 'grafana.local:8443:127.0.0.1' \
            https://grafana.local:8443/api/health -w '%{http_code}' -o /dev/null 2>/dev/null)"
        [ "$status" = "200" ] && break
        sleep 5
    done
    run echo "$status"
    [ "$output" = "200" ]

    # Cleanup
    kubectl --context k3s-lima delete -f "$LIMA_DIR/smoke-monitoring.yaml" --ignore-not-found >/dev/null 2>&1
}
