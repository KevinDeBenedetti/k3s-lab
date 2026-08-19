#!/usr/bin/env bats
# tests/bats/inventory-ignored.bats — Tests for scripts/check-inventory-ignored.sh
#
# Each case builds a throwaway git repository in BATS_TEST_TMPDIR and points the
# script at it with --repo, so the assertions run against real `git ls-files` and
# `git check-ignore` behaviour rather than a stub. That matters here: the
# subtlety being guarded — a .gitignore rule not applying to already-tracked
# files — is git's own semantics, and a stub would merely encode my belief about
# it.
#
# "Tracked" is established with `git add -f` alone: `git ls-files` reports the
# INDEX, so staging is enough to reproduce the condition the check looks for,
# and it keeps each fixture to a single command.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-inventory-ignored.sh"

setup() {
  FIX="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FIX}/ansible/inventory/group_vars"
  git -C "$FIX" init -q
  printf 'ansible/inventory/\n' > "${FIX}/.gitignore"
}

# writes the two generated files, as generate-inventory.sh would
generate() {
  printf 'all:\n  hosts:\n    srv: {ansible_host: 1.2.3.4}\n' > "${FIX}/ansible/inventory/hosts.yml"
  printf 'k3s_version: v1.36.3\n' > "${FIX}/ansible/inventory/group_vars/all.yml"
}

run_check() { run "$SCRIPT" --repo "$FIX"; }

@test "passes when the inventory is ignored and untracked" {
  generate
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored and untracked"* ]]
}

@test "passes on a fresh clone where the inventory does not exist yet" {
  run_check
  [ "$status" -eq 0 ]
}

@test "fails when an inventory file is tracked" {
  generate
  git -C "$FIX" add -f ansible/inventory/hosts.yml
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"TRACKED"* ]]
  [[ "$output" == *"hosts.yml"* ]]
}

@test "the tracked message explains that .gitignore does not apply retroactively" {
  generate
  git -C "$FIX" add -f ansible/inventory/group_vars/all.yml
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not apply to already-tracked files"* ]]
  [[ "$output" == *"--cached"* ]]
}

@test "fails when the ignore rule no longer matches" {
  : > "${FIX}/.gitignore"
  generate
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT ignored"* ]]
  [[ "$output" == *"git add -A"* ]]
}

@test "a rule covering only one of the two paths is still a failure" {
  printf 'ansible/inventory/hosts.yml\n' > "${FIX}/.gitignore"
  generate
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"group_vars/all.yml"* ]]
}

@test "fails when the generator writes a path the check does not guard" {
  mkdir -p "${FIX}/scripts"
  cat > "${FIX}/scripts/generate-inventory.sh" <<'EOF'
#!/usr/bin/env bash
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.yml"
GROUP_VARS_FILE="${ANSIBLE_DIR}/inventory/group_vars/all.yml"
SECRET_FILE="${ANSIBLE_DIR}/inventory/host_vars/server.yml"
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"host_vars/server.yml"* ]]
  [[ "$output" == *"does not guard"* ]]
}

@test "a generator whose paths cannot be parsed is refused, not passed" {
  mkdir -p "${FIX}/scripts"
  printf '#!/usr/bin/env bash\necho nothing parseable here\n' \
    > "${FIX}/scripts/generate-inventory.sh"
  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"verified nothing"* ]]
}

@test "a missing repository directory is a usage error" {
  run "$SCRIPT" --repo "${BATS_TEST_TMPDIR}/nope"
  [ "$status" -eq 2 ]
}
