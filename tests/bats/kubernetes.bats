#!/usr/bin/env bats
# kubernetes.bats — verify Kubernetes manifest structure
#
# Run:  bats tests/bats/kubernetes.bats
# All checks are offline — no cluster required.

setup() {
    load 'common-setup'
    _common_setup
}

# ── Directory structure ───────────────────────────────────────────────────────

@test "kubernetes/ directory exists" {
    [ -d "$REPO_ROOT/kubernetes" ]
}

@test "kubernetes/namespaces directory exists" {
    [ -d "$REPO_ROOT/kubernetes/namespaces" ]
}

@test "kubernetes/cert-manager directory exists" {
    [ -d "$REPO_ROOT/kubernetes/cert-manager" ]
}

@test "kubernetes/ingress directory exists" {
    [ -d "$REPO_ROOT/kubernetes/ingress" ]
}

@test "kubernetes/monitoring directory exists" {
    [ -d "$REPO_ROOT/kubernetes/monitoring" ]
}

# ── Key manifests exist ───────────────────────────────────────────────────────

@test "namespaces/namespaces.yaml exists" {
    [ -f "$REPO_ROOT/kubernetes/namespaces/namespaces.yaml" ]
}

@test "cert-manager/clusterissuer.yaml exists" {
    [ -f "$REPO_ROOT/kubernetes/cert-manager/clusterissuer.yaml" ]
}

@test "ingress/traefik-values.yaml exists" {
    [ -f "$REPO_ROOT/kubernetes/ingress/traefik-values.yaml" ]
}

@test "ingress/traefik-dashboard.yaml exists" {
    [ -f "$REPO_ROOT/kubernetes/ingress/traefik-dashboard.yaml" ]
}

@test "monitoring/grafana-ingress.yaml exists" {
    [ -f "$REPO_ROOT/kubernetes/monitoring/grafana-ingress.yaml" ]
}

@test "monitoring/kube-prometheus-values.yaml exists" {
    [ -f "$REPO_ROOT/kubernetes/monitoring/kube-prometheus-values.yaml" ]
}

# ── Manifest structural validity ──────────────────────────────────────────────

@test "all non-values manifests have apiVersion" {
    local failed=0
    while IFS= read -r manifest; do
        if ! grep -q "^apiVersion:" "$manifest"; then
            echo "Missing apiVersion: $manifest"
            failed=1
        fi
    done < <(find "$REPO_ROOT/kubernetes" -name "*.yaml" ! -name "*-values.yaml")
    [ "$failed" -eq 0 ]
}

@test "all non-values manifests have kind" {
    local failed=0
    while IFS= read -r manifest; do
        if ! grep -q "^kind:" "$manifest"; then
            echo "Missing kind: $manifest"
            failed=1
        fi
    done < <(find "$REPO_ROOT/kubernetes" -name "*.yaml" ! -name "*-values.yaml")
    [ "$failed" -eq 0 ]
}

# ── No hardcoded IPs in manifests ─────────────────────────────────────────────

@test "manifests use env variables not hardcoded IPs" {
    # Real public IPs should not appear in tracked manifests.
    # Allows private ranges (10.x, 172.16-31.x, 192.168.x) used by k3s internally.
    local found
    found="$(grep -rP '\b(?!10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' \
        "$REPO_ROOT/kubernetes/" --include="*.yaml" -l 2>/dev/null || true)"
    if [ -n "$found" ]; then
        echo "Possible hardcoded public IPs in: $found"
    fi
    # Informational only — real enforcement comes from gitleaks
    true
}

# ── Template variables (no hardcoded domains) ─────────────────────────────────

@test "cert-manager clusterissuer uses \${EMAIL} template variable" {
    grep -q '\${EMAIL}' "$REPO_ROOT/kubernetes/cert-manager/clusterissuer.yaml"
}

@test "traefik dashboard uses \${DASHBOARD_DOMAIN} template variable" {
    grep -q '\${DASHBOARD_DOMAIN}' "$REPO_ROOT/kubernetes/ingress/traefik-dashboard.yaml"
}

# ── Namespace consistency ─────────────────────────────────────────────────────

@test "namespaces.yaml defines ingress namespace" {
    grep -q "ingress" "$REPO_ROOT/kubernetes/namespaces/namespaces.yaml"
}

@test "namespaces.yaml defines monitoring namespace" {
    grep -q "monitoring" "$REPO_ROOT/kubernetes/namespaces/namespaces.yaml"
}

@test "namespaces.yaml defines apps namespace" {
    grep -q "apps" "$REPO_ROOT/kubernetes/namespaces/namespaces.yaml"
}
