#!/usr/bin/env bats
# tests/bats/vault.bats — lib/vault.sh and the scripts built on it, run end to
# end against tests/bats/helpers/fake-vault-kubectl at the KUBECTL seam.
#
# The fake keeps Vault's state (initialised, sealed, mounts, unseal threshold)
# in a directory and records every call's argv and stdin, so a test can assert
# both what Vault ended up with and how the secrets travelled.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  export FAKE_VAULT_DIR="${BATS_TEST_TMPDIR}/vault"
  mkdir -p "$FAKE_VAULT_DIR"
  export KUBECTL="${REPO_ROOT}/tests/bats/helpers/fake-vault-kubectl"
  # An empty project directory: no .env is read from the developer's checkout.
  export K3S_LAB_PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
  mkdir -p "$K3S_LAB_PROJECT_DIR"
  cd "$K3S_LAB_PROJECT_DIR"
  unset VAULT_ROOT_TOKEN VAULT_TOKEN VAULT_POLICY_DIR K3S_LAB_ENV_FILE \
    VAULT_UNSEAL_KEY_1 VAULT_UNSEAL_KEY_2 VAULT_UNSEAL_KEY_3 \
    OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_ISSUER_URL VAULT_DOMAIN ADMIN_EMAIL
}

# An initialised, unsealed Vault whose root token is "root-token-xyz".
vault_ready() {
  echo true >"$FAKE_VAULT_DIR/initialized"
  echo false >"$FAKE_VAULT_DIR/sealed"
  echo root-token-xyz >"$FAKE_VAULT_DIR/root_token"
  export VAULT_ROOT_TOKEN=root-token-xyz
}

all_oidc() {
  export OIDC_CLIENT_ID=client-id OIDC_CLIENT_SECRET=client-secret-abc \
    OIDC_ISSUER_URL=https://issuer.example.test VAULT_DOMAIN=vault.example.test \
    ADMIN_EMAIL=admin@example.test
}

calls() { cat "$FAKE_VAULT_DIR/calls"; }
writes() { cat "$FAKE_VAULT_DIR/writes" 2>/dev/null; }

# refute <pattern> <file> — fail the test when the file contains the pattern.
# Not `! grep …`: bash ignores `set -e` for a negated command, so such a line
# can never fail a bats test unless it happens to be the last one.
refute() {
  if grep -q -- "$1" "$2" 2>/dev/null; then
    echo "unexpected '$1' in $2:"; grep -- "$1" "$2"
    return 1
  fi
}

# ── Secrets travel on stdin only ─────────────────────────────────────────────

@test "the root token, unseal keys and OIDC secret never appear in kubectl's arguments" {
  all_oidc
  run "${REPO_ROOT}/scripts/vault-init.sh"
  [ "$status" -eq 0 ]
  refute 'root-token-xyz' "$FAKE_VAULT_DIR/calls"
  refute 'unseal-key-' "$FAKE_VAULT_DIR/calls"
  refute 'client-secret-abc' "$FAKE_VAULT_DIR/calls"
  # …and they did reach Vault, on stdin
  grep -lq 'root-token-xyz' "$FAKE_VAULT_DIR"/stdin.*
  grep -lq 'unseal-key-1' "$FAKE_VAULT_DIR"/stdin.*
  grep -lq 'client-secret-abc' "$FAKE_VAULT_DIR"/stdin.*
}

# ── Configure ────────────────────────────────────────────────────────────────

@test "configure enables KV and Kubernetes auth, writes policies and the eso role" {
  vault_ready
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 0 ]
  grep -qx 'secret/' "$FAKE_VAULT_DIR/mounts"
  grep -qx 'auth:kubernetes/' "$FAKE_VAULT_DIR/mounts"
  writes | grep -qx 'auth/kubernetes/config'
  writes | grep -qx 'auth/kubernetes/role/eso'
  [ -f "$FAKE_VAULT_DIR/policies/eso-read" ]
  grep -q 'secret/data/\*' "$FAKE_VAULT_DIR/policies/eso-read"
}

@test "configure skips mounts that exist but still rewrites their config" {
  vault_ready
  printf 'secret/\nauth:kubernetes/\n' >"$FAKE_VAULT_DIR/mounts"
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 0 ]
  refute 'secrets | enable' "$FAKE_VAULT_DIR/calls"
  refute 'auth | enable | kubernetes' "$FAKE_VAULT_DIR/calls"
  writes | grep -qx 'auth/kubernetes/config'
  [[ "$output" == *"KV v2 already enabled"* ]]
}

@test "configure refuses a sealed Vault" {
  vault_ready
  echo true >"$FAKE_VAULT_DIR/sealed"
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Vault is sealed"* ]]
}

@test "configure refuses an invalid root token" {
  vault_ready
  export VAULT_ROOT_TOKEN=wrong-token
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid or expired root token"* ]]
}

# ── OIDC: all five, none, or refuse ──────────────────────────────────────────

@test "OIDC: all five variables configure it, with the vault-admin policy" {
  vault_ready
  all_oidc
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 0 ]
  grep -qx 'auth:oidc/' "$FAKE_VAULT_DIR/mounts"
  writes | grep -qx 'auth/oidc/config'
  writes | grep -qx 'auth/oidc/role/default'
  [ -f "$FAKE_VAULT_DIR/policies/vault-admin" ]
  calls | grep -q 'bound_claims={"email":"admin@example.test"}'
}

@test "OIDC: none set skips it" {
  vault_ready
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 0 ]
  refute 'auth:oidc/' "$FAKE_VAULT_DIR/mounts"
  refute 'auth/oidc' "$FAKE_VAULT_DIR/writes"
  [[ "$output" == *"Skipping OIDC"* ]]
}

@test "OIDC: a partial set is refused before anything is written, naming what is missing" {
  vault_ready
  all_oidc
  unset OIDC_CLIENT_SECRET VAULT_DOMAIN
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OIDC_CLIENT_SECRET"* ]]
  [[ "$output" == *"VAULT_DOMAIN"* ]]
  [ -z "$(writes)" ]
  [ ! -s "$FAKE_VAULT_DIR/mounts" ]
}

# ── Policy directory ─────────────────────────────────────────────────────────

@test "VAULT_POLICY_DIR replaces the shipped policies, extra files included" {
  vault_ready
  export VAULT_POLICY_DIR="${BATS_TEST_TMPDIR}/policies"
  mkdir -p "$VAULT_POLICY_DIR"
  printf 'path "secret/data/apps/*" { capabilities = ["read"] }\n' >"$VAULT_POLICY_DIR/eso-read.hcl"
  printf 'path "secret/data/ci/*" { capabilities = ["read"] }\n' >"$VAULT_POLICY_DIR/ci-read.hcl"
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 0 ]
  grep -q 'secret/data/apps/\*' "$FAKE_VAULT_DIR/policies/eso-read"
  [ -f "$FAKE_VAULT_DIR/policies/ci-read" ]
  [ ! -f "$FAKE_VAULT_DIR/policies/vault-admin" ]
}

@test "a policy directory without eso-read.hcl is refused" {
  vault_ready
  export VAULT_POLICY_DIR="${BATS_TEST_TMPDIR}/policies"
  mkdir -p "$VAULT_POLICY_DIR"
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"eso-read.hcl"* ]]
  [ -z "$(writes)" ]
}

@test "with OIDC on, a policy directory without vault-admin.hcl is refused" {
  vault_ready
  all_oidc
  export VAULT_POLICY_DIR="${BATS_TEST_TMPDIR}/policies"
  mkdir -p "$VAULT_POLICY_DIR"
  cp "${REPO_ROOT}/vault/policies/eso-read.hcl" "$VAULT_POLICY_DIR/"
  run "${REPO_ROOT}/scripts/vault-configure.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vault-admin.hcl"* ]]
}

# ── Init ─────────────────────────────────────────────────────────────────────

@test "init on a fresh Vault prints the keys, unseals with the threshold, then configures" {
  run "${REPO_ROOT}/scripts/vault-init.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unseal Key 1: unseal-key-1"* ]]
  [[ "$output" == *"Unseal Key 3: unseal-key-3"* ]]
  [[ "$output" == *"Root Token:   root-token-xyz"* ]]
  calls | grep -q 'operator | init | -key-shares=3 | -key-threshold=2'
  [ "$(cat "$FAKE_VAULT_DIR/sealed")" = "false" ]
  # exactly the threshold number of keys, not all three
  [ "$(wc -l <"$FAKE_VAULT_DIR/accepted" | tr -d ' ')" -eq 2 ]
  writes | grep -qx 'auth/kubernetes/role/eso'
}

@test "init honours VAULT_KEY_SHARES and VAULT_KEY_THRESHOLD" {
  VAULT_KEY_SHARES=5 VAULT_KEY_THRESHOLD=3 run "${REPO_ROOT}/scripts/vault-init.sh"
  [ "$status" -eq 0 ]
  calls | grep -q 'operator | init | -key-shares=5 | -key-threshold=3'
  [ "$(wc -l <"$FAKE_VAULT_DIR/accepted" | tr -d ' ')" -eq 3 ]
}

@test "init on an initialised, sealed Vault unseals from the environment and configures" {
  vault_ready
  echo true >"$FAKE_VAULT_DIR/sealed"
  export VAULT_UNSEAL_KEY_1=k-one VAULT_UNSEAL_KEY_2=k-two
  run "${REPO_ROOT}/scripts/vault-init.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
  refute 'operator | init' "$FAKE_VAULT_DIR/calls"
  [ "$(cat "$FAKE_VAULT_DIR/sealed")" = "false" ]
  writes | grep -qx 'auth/kubernetes/role/eso'
}

# ── Unseal ───────────────────────────────────────────────────────────────────

@test "unseal stops as soon as Vault reports unsealed" {
  vault_ready
  echo true >"$FAKE_VAULT_DIR/sealed"
  echo 2 >"$FAKE_VAULT_DIR/threshold"
  export VAULT_UNSEAL_KEY_1=k-one VAULT_UNSEAL_KEY_2=k-two VAULT_UNSEAL_KEY_3=k-three
  run "${REPO_ROOT}/scripts/vault-unseal.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_VAULT_DIR/accepted")" = "$(printf 'k-one\nk-two')" ]
}

@test "unseal does nothing on an unsealed Vault" {
  vault_ready
  run "${REPO_ROOT}/scripts/vault-unseal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already unsealed"* ]]
  [ ! -s "$FAKE_VAULT_DIR/accepted" ]
}

@test "unseal fails when Vault does not answer" {
  export KUBECTL="${BATS_TEST_TMPDIR}/dead-kubectl"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$KUBECTL"
  chmod +x "$KUBECTL"
  run "${REPO_ROOT}/scripts/vault-unseal.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot reach Vault"* ]]
}

# ── Seed ─────────────────────────────────────────────────────────────────────

@test "seed reuses the module's exec, reads .env, and skips unset values" {
  vault_ready
  printf 'GRAFANA_PASSWORD=from-dotenv\n' >"${K3S_LAB_PROJECT_DIR}/.env"
  run "${REPO_ROOT}/scripts/vault-seed.sh"
  [ "$status" -eq 0 ]
  writes | grep -qx 'secret/grafana/admin'
  refute 'secret/argocd/oidc' "$FAKE_VAULT_DIR/writes"
  [[ "$output" == *"skipped argocd/oidc"* ]]
  refute 'root-token-xyz' "$FAKE_VAULT_DIR/calls"
}
