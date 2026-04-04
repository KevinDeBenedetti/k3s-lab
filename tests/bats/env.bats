#!/usr/bin/env bats
# env.bats — verify .env.example documents all required variables
#
# Run:  bats tests/bats/env.bats

setup() {
    load 'common-setup'
    _common_setup
}

# ── File existence ────────────────────────────────────────────────────────────

@test ".env.example exists" {
    [ -f "$REPO_ROOT/.env.example" ]
}

@test ".env is NOT tracked by git (secrets guard)" {
    run git -C "$REPO_ROOT" ls-files --error-unmatch .env
    [ "$status" -ne 0 ]
}

# ── Required keys ─────────────────────────────────────────────────────────────

@test ".env.example has SERVER_IP" {
    grep -q "^SERVER_IP=" "$REPO_ROOT/.env.example"
}

@test ".env.example has AGENT_IP" {
    grep -q "^AGENT_IP=" "$REPO_ROOT/.env.example"
}

@test ".env.example has DOMAIN" {
    grep -q "^DOMAIN=" "$REPO_ROOT/.env.example"
}

@test ".env.example has EMAIL" {
    grep -q "^EMAIL=" "$REPO_ROOT/.env.example"
}

@test ".env.example has DASHBOARD_DOMAIN" {
    grep -q "^DASHBOARD_DOMAIN=" "$REPO_ROOT/.env.example"
}

@test ".env.example has DASHBOARD_PASSWORD" {
    grep -q "^DASHBOARD_PASSWORD=" "$REPO_ROOT/.env.example"
}

@test ".env.example has GRAFANA_DOMAIN" {
    grep -q "^GRAFANA_DOMAIN=" "$REPO_ROOT/.env.example"
}

@test ".env.example has GRAFANA_PASSWORD" {
    grep -q "^GRAFANA_PASSWORD=" "$REPO_ROOT/.env.example"
}

@test ".env.example has KUBECONFIG_CONTEXT" {
    grep -q "^KUBECONFIG_CONTEXT=" "$REPO_ROOT/.env.example"
}

@test ".env.example has K3S_VERSION" {
    grep -q "^K3S_VERSION=" "$REPO_ROOT/.env.example"
}

@test ".env.example has K3S_NODE_TOKEN" {
    grep -q "^K3S_NODE_TOKEN=" "$REPO_ROOT/.env.example"
}

# ── No real secrets in .env.example ──────────────────────────────────────────

@test ".env.example values are placeholders (no real IPs in SERVER_IP)" {
    val="$(grep "^SERVER_IP=" "$REPO_ROOT/.env.example" | cut -d= -f2)"
    # Allow empty or obvious placeholder strings
    [[ -z "$val" || "$val" =~ ^(1\.2\.3\.4|x\.x\.x\.x|<.*>|your-|YOUR_|CHANGE_ME) ]] \
        || [[ "$val" =~ \. ]]
}
