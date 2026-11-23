#!/usr/bin/env bats
# tests/bats/ssh-node.bats — scripts/ssh-node.sh, the shell behind
# `task ssh:server|agent`, against a fake ssh (the SSH seam) that prints the
# arguments it got, one per line. Until #130 the tasks ran
# `ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SERVER_IP` with no defaults: an
# unset SSH_PORT made `-p` swallow the host, an unset SSH_KEY made `-i`
# swallow `-p`.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ssh-node.sh"

setup() {
  export SSH="${BATS_TEST_TMPDIR}/ssh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' >"$SSH"
  chmod +x "$SSH"
  export K3S_LAB_PROJECT_DIR="$BATS_TEST_TMPDIR"
  cd "$BATS_TEST_TMPDIR"
  unset SSH_USER SSH_PORT SSH_KEY K3S_LAB_ENV_FILE
  export USER=localme
}

@test "with only a host, the user is the local one and the port 22" {
  run "$SCRIPT" 192.0.2.10
  [ "$status" -eq 0 ]
  [[ "$output" == *$'-p\n22'* ]]
  [ "${lines[-1]}" = "localme@192.0.2.10" ]
  [[ "$output" != *"-i"* ]]
}

@test "SSH_USER, SSH_PORT and SSH_KEY are applied when set" {
  SSH_USER=debian SSH_PORT=2222 SSH_KEY=/keys/id run "$SCRIPT" 192.0.2.10
  [ "$status" -eq 0 ]
  [[ "$output" == *$'-p\n2222'* ]]
  [[ "$output" == *$'-i\n/keys/id'* ]]
  [ "${lines[-1]}" = "debian@192.0.2.10" ]
}

@test "new hosts are trusted on first contact, changed keys are not" {
  run "$SCRIPT" 192.0.2.10
  [[ "$output" == *"StrictHostKeyChecking=accept-new"* ]]
}

@test "a missing host is a usage error that names the variable" {
  run "$SCRIPT" ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"host"* ]]
}
