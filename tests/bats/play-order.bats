#!/usr/bin/env bats
# tests/bats/play-order.bats — Tests for scripts/check-play-order.sh
#
# The script shells out to `ansible-playbook --list-tasks`, which this suite
# stubs through the ANSIBLE_PLAYBOOK injection point so the tests run in the
# shell-ci job, where ansible is not installed. The stub prints a canned listing
# per playbook, in ansible's real `--list-tasks` format.
#
# The invariant under test is the one that costs a rescue-console session when it
# breaks: UFW is enabled by the `ufw_enable` role in the final play, after every
# other role has registered its rules. Both ways of breaking it are covered —
# scheduling something after the enabler, and dropping the enabler altogether —
# because they fail differently and the message has to say which.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-play-order.sh"

setup() {
  PB="${BATS_TEST_TMPDIR}/ansible/playbooks"
  FIX="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "$PB" "$FIX"

  STUB="${BATS_TEST_TMPDIR}/ansible-playbook"
  cat > "$STUB" <<EOF
#!/usr/bin/env bash
for arg; do :; done          # last argument is the playbook path
name="\$(basename "\$arg")"
[ -f "${FIX}/\$name" ] || exit 1
cat "${FIX}/\$name"
EOF
  chmod +x "$STUB"
  export ANSIBLE_PLAYBOOK="$STUB"
}

# playbook NAME <<< listing
playbook() {
  : > "${PB}/$1"
  cat > "${FIX}/$1"
}

run_check() { run "$SCRIPT" --playbooks "$PB"; }

@test "passes when the playbook ends with the ufw_enable role" {
  playbook site.yml <<'EOF'
  play #1 (all): Base setup	TAGS: []
    tasks:
      common : Apply sysctl settings	TAGS: []
      common : Set UFW default incoming policy	TAGS: []
  play #2 (all): Enable the firewall	TAGS: []
    tasks:
      ufw_enable : Enable UFW	TAGS: [ufw]
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"enables the firewall last"* ]]
}

@test "fails when a role is scheduled after ufw_enable" {
  playbook site.yml <<'EOF'
  play #1 (all): Base setup	TAGS: []
    tasks:
      common : Set UFW default incoming policy	TAGS: []
  play #2 (all): Enable the firewall	TAGS: []
    tasks:
      ufw_enable : Enable UFW	TAGS: [ufw]
  play #3 (all): Added later	TAGS: []
    tasks:
      latecomer : Something added later	TAGS: []
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"last role to run is 'latecomer'"* ]]
  [[ "$output" == *"something is scheduled after it"* ]]
}

@test "fails, differently, when ufw_enable never runs" {
  playbook site.yml <<'EOF'
  play #1 (all): Base setup	TAGS: []
    tasks:
      common : Set UFW default incoming policy	TAGS: []
      k3s_server : Open firewall ports for agents	TAGS: []
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"never runs at all"* ]]
  [[ "$output" == *"staged behind a firewall nobody turns on"* ]]
}

@test "refuses a playbook that enables the firewall twice" {
  playbook site.yml <<'EOF'
  play #1 (all): Enable early	TAGS: []
    tasks:
      ufw_enable : Enable UFW	TAGS: [ufw]
  play #2 (all): Rules	TAGS: []
    tasks:
      common : Set UFW default incoming policy	TAGS: []
  play #3 (all): Enable again	TAGS: []
    tasks:
      ufw_enable : Enable UFW	TAGS: [ufw]
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"runs 2 times"* ]]
}

@test "a playbook applying no role at all is not required to enable anything" {
  playbook reset.yml <<'EOF'
  play #1 (k3s_agents): Uninstall k3s agents	TAGS: []
    tasks:
      Check for k3s-agent-uninstall script	TAGS: []
      Run k3s agent uninstall	TAGS: []
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"applies no role"* ]]
}

@test "a playbook whose roles add no UFW rule is not required to enable anything" {
  playbook docs.yml <<'EOF'
  play #1 (all): Something unrelated	TAGS: []
    tasks:
      motd : Deploy dynamic MOTD script	TAGS: []
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"adds no UFW rule"* ]]
}

@test "every offending playbook is reported, not just the first" {
  playbook a.yml <<'EOF'
  play #1 (all): Rules	TAGS: []
    tasks:
      common : Set UFW default incoming policy	TAGS: []
EOF
  playbook b.yml <<'EOF'
  play #1 (all): Rules	TAGS: []
    tasks:
      wireguard : Open WireGuard port in UFW	TAGS: []
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.yml"* ]]
  [[ "$output" == *"b.yml"* ]]
  [[ "$output" == *"2 playbook(s)"* ]]
}

@test "a --list-tasks that fails is an error, not a silent pass" {
  : > "${PB}/site.yml"   # no fixture, so the stub exits 1
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not be checked"* ]]
}

@test "a playbook directory with no playbooks is refused rather than passed vacuously" {
  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"No playbook found"* ]]
}

@test "a missing playbook directory is a usage error" {
  run "$SCRIPT" --playbooks "${BATS_TEST_TMPDIR}/nope"
  [ "$status" -eq 2 ]
}
