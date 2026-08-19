#!/usr/bin/env bats
# tests/bats/ansible-collections.bats — Tests for scripts/check-ansible-collections.sh
#
# The script asks a question about the machine it runs on, so these tests stub
# `ansible-galaxy` through the ANSIBLE_GALAXY injection point: the stub prints a
# canned `collection list --format json` document written per-case. That keeps
# every scenario declarative and lets the suite run on a machine with no
# collections installed at all.
#
# The case worth the most here is the shadowing one. `ansible-galaxy collection
# list` reports every path it searched, and ansible resolves the FIRST match —
# so a collection present twice at different versions is not ambiguous, it has a
# definite answer, and reporting the wrong one would make the check lie in the
# exact situation it was written for.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-ansible-collections.sh"

setup() {
  REQ="${BATS_TEST_TMPDIR}/requirements.yml"
  cat > "$REQ" <<'EOF'
---
collections:
  - name: community.general
    version: "12.5.0"
  - name: ansible.posix
    version: "2.1.0"
EOF

  GALAXY_OUT="${BATS_TEST_TMPDIR}/galaxy.json"
  STUB="${BATS_TEST_TMPDIR}/ansible-galaxy"
  cat > "$STUB" <<EOF
#!/usr/bin/env bash
cat "${GALAXY_OUT}"
EOF
  chmod +x "$STUB"
  export ANSIBLE_GALAXY="$STUB"
}

run_check() { run "$SCRIPT" --requirements "$REQ"; }

@test "passes when every pinned collection is installed at the pinned version" {
  cat > "$GALAXY_OUT" <<'EOF'
{"/home/u/.ansible/collections/ansible_collections":
  {"community.general": {"version": "12.5.0"}, "ansible.posix": {"version": "2.1.0"}}}
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"All 2 pinned collection(s)"* ]]
}

@test "fails when a pinned collection is not installed at all" {
  cat > "$GALAXY_OUT" <<'EOF'
{"/home/u/.ansible/collections/ansible_collections":
  {"ansible.posix": {"version": "2.1.0"}}}
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"community.general"* ]]
  [[ "$output" == *"NOT INSTALLED"* ]]
}

@test "the missing-collection message names the misleading ansible-lint error" {
  cat > "$GALAXY_OUT" <<'EOF'
{"/p": {"ansible.posix": {"version": "2.1.0"}}}
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't resolve module/action"* ]]
}

@test "fails when a collection is installed at the wrong version" {
  cat > "$GALAXY_OUT" <<'EOF'
{"/p": {"community.general": {"version": "13.3.0"}, "ansible.posix": {"version": "2.1.0"}}}
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"pinned at 12.5.0, resolves to 13.3.0"* ]]
}

@test "reports every mismatch, not just the first" {
  cat > "$GALAXY_OUT" <<'EOF'
{"/p": {"community.general": {"version": "13.3.0"}, "ansible.posix": {"version": "2.2.2"}}}
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"community.general"* ]]
  [[ "$output" == *"ansible.posix"* ]]
  [[ "$output" == *"2 collection(s) do not match"* ]]
}

@test "a collection present twice resolves to the earliest path, and is reported as such" {
  # Homebrew's bundled 13.3.0 sitting in front of the pinned 12.5.0.
  cat > "$GALAXY_OUT" <<'EOF'
{"/usr/lib/python3/site-packages/ansible_collections":
   {"community.general": {"version": "13.3.0"}, "ansible.posix": {"version": "2.1.0"}},
 "/home/u/.ansible/collections/ansible_collections":
   {"community.general": {"version": "12.5.0"}}}
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"resolves to 13.3.0"* ]]
}

@test "the pinned copy earlier in the path is accepted even when an older one follows" {
  cat > "$GALAXY_OUT" <<'EOF'
{"/home/u/.ansible/collections/ansible_collections":
   {"community.general": {"version": "12.5.0"}, "ansible.posix": {"version": "2.1.0"}},
 "/usr/lib/python3/site-packages/ansible_collections":
   {"community.general": {"version": "9.0.0"}}}
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "a requirements file pinning nothing is refused rather than passed vacuously" {
  cat > "$REQ" <<'EOF'
---
collections: []
EOF
  cat > "$GALAXY_OUT" <<'EOF'
{"/p": {}}
EOF
  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"checked nothing"* ]]
}

@test "a requirement with no version pinned is not asserted" {
  cat > "$REQ" <<'EOF'
---
collections:
  - name: community.general
    version: "12.5.0"
  - name: community.docker
EOF
  cat > "$GALAXY_OUT" <<'EOF'
{"/p": {"community.general": {"version": "12.5.0"}}}
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 collection(s) pinned"* ]]
}

@test "a missing requirements file is a usage error" {
  run "$SCRIPT" --requirements "${BATS_TEST_TMPDIR}/nope.yml"
  [ "$status" -eq 2 ]
}

@test "an ansible-galaxy that fails is an error, not an empty pass" {
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$STUB"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed"* ]]
}

@test "non-JSON output from ansible-galaxy is refused" {
  cat > "$GALAXY_OUT" <<'EOF'
not json at all
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not return JSON"* ]]
}
