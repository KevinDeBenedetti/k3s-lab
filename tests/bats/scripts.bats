#!/usr/bin/env bats
# scripts.bats — verify shell script hygiene
#
# Run:  bats tests/bats/scripts.bats

setup() {
    load 'common-setup'
    _common_setup
}

# ── Required scripts exist ────────────────────────────────────────────────────

@test "k3s/install-master.sh exists" {
    [ -f "$REPO_ROOT/k3s/install-master.sh" ]
}

@test "k3s/install-worker.sh exists" {
    [ -f "$REPO_ROOT/k3s/install-worker.sh" ]
}

@test "k3s/uninstall.sh exists" {
    [ -f "$REPO_ROOT/k3s/uninstall.sh" ]
}

@test "scripts/deploy-stack.sh exists" {
    [ -f "$REPO_ROOT/scripts/deploy-stack.sh" ]
}

@test "scripts/deploy-monitoring.sh exists" {
    [ -f "$REPO_ROOT/scripts/deploy-monitoring.sh" ]
}

@test "scripts/get-kubeconfig.sh exists" {
    [ -f "$REPO_ROOT/scripts/get-kubeconfig.sh" ]
}

@test "scripts/setup-vps.sh exists" {
    [ -f "$REPO_ROOT/scripts/setup-vps.sh" ]
}

@test "lib/load-env.sh exists" {
    [ -f "$REPO_ROOT/lib/load-env.sh" ]
}

@test "lib/log.sh exists" {
    [ -f "$REPO_ROOT/lib/log.sh" ]
}

@test "lib/ssh-opts.sh exists" {
    [ -f "$REPO_ROOT/lib/ssh-opts.sh" ]
}

@test "lib/run-mode.sh exists" {
    [ -f "$REPO_ROOT/lib/run-mode.sh" ]
}

# ── All .sh files have shebangs ───────────────────────────────────────────────

@test "all executable .sh files have a shebang on line 1" {
    local failed=0
    # lib/ files are sourced-only helpers and don't require a shebang
    while IFS= read -r file; do
        if ! head -1 "$file" | grep -q '^#!'; then
            echo "Missing shebang: $file"
            failed=1
        fi
    done < <(find "$REPO_ROOT" -name "*.sh" -not -path "*/.git/*" -not -path "*/lib/*")
    [ "$failed" -eq 0 ]
}

# ── All .sh files are executable ─────────────────────────────────────────────

@test "all executable .sh files are executable" {
    local failed=0
    # lib/ files are sourced-only helpers and do not need the executable bit
    while IFS= read -r file; do
        if [ ! -x "$file" ]; then
            echo "Not executable: $file"
            failed=1
        fi
    done < <(find "$REPO_ROOT" -name "*.sh" -not -path "*/.git/*" -not -path "*/lib/*")
    [ "$failed" -eq 0 ]
}

# ── Script content checks ─────────────────────────────────────────────────────

@test "install-master.sh sets -euo pipefail" {
    grep -q "set -euo pipefail" "$REPO_ROOT/k3s/install-master.sh"
}

@test "install-worker.sh sets -euo pipefail" {
    grep -q "set -euo pipefail" "$REPO_ROOT/k3s/install-worker.sh"
}

@test "deploy-stack.sh sets -euo pipefail" {
    grep -q "set -euo pipefail" "$REPO_ROOT/scripts/deploy-stack.sh"
}

@test "deploy-monitoring.sh sets -euo pipefail" {
    grep -q "set -euo pipefail" "$REPO_ROOT/scripts/deploy-monitoring.sh"
}

@test "get-kubeconfig.sh sets -euo pipefail" {
    grep -q "set -euo pipefail" "$REPO_ROOT/scripts/get-kubeconfig.sh"
}

@test "setup-vps.sh sets -euo pipefail" {
    grep -q "set -euo pipefail" "$REPO_ROOT/scripts/setup-vps.sh"
}

# ── lib helpers are sourceable ────────────────────────────────────────────────

@test "lib/load-env.sh defines load_env function" {
    run bash -c "source '$REPO_ROOT/lib/load-env.sh' && declare -f load_env"
    [ "$status" -eq 0 ]
}

@test "lib/log.sh defines log_ok function" {
    run bash -c "source '$REPO_ROOT/lib/log.sh' && declare -f log_ok"
    [ "$status" -eq 0 ]
}

@test "lib/ssh-opts.sh defines build_ssh_opts function" {
    run bash -c "source '$REPO_ROOT/lib/ssh-opts.sh' && declare -f build_ssh_opts"
    [ "$status" -eq 0 ]
}
