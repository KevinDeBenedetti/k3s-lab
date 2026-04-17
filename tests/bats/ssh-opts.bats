#!/usr/bin/env bats
# tests/bats/ssh-opts.bats — Unit tests for lib/ssh-opts.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/ssh-opts.sh"
  unset SSH_KEY SSH_PORT SSH_OPTS
}

@test "build_ssh_opts sets default port 22" {
  build_ssh_opts || true
  [[ " ${SSH_OPTS[*]} " == *"-p 22"* ]]
}

@test "build_ssh_opts uses custom port" {
  build_ssh_opts 2222 || true
  [[ " ${SSH_OPTS[*]} " == *"-p 2222"* ]]
}

@test "build_ssh_opts sets StrictHostKeyChecking" {
  build_ssh_opts 22 "no" || true
  [[ " ${SSH_OPTS[*]} " == *"StrictHostKeyChecking=no"* ]]
}

@test "build_ssh_opts does not add ConnectTimeout when 0" {
  build_ssh_opts 22 accept-new 0 || true
  [[ " ${SSH_OPTS[*]} " != *"ConnectTimeout"* ]]
}

@test "build_ssh_opts adds ConnectTimeout when > 0" {
  build_ssh_opts 22 accept-new 15 || true
  [[ " ${SSH_OPTS[*]} " == *"ConnectTimeout=15"* ]]
}

@test "build_ssh_opts adds identity file when SSH_KEY is set" {
  SSH_KEY=~/.ssh/id_ed25519
  build_ssh_opts
  [[ " ${SSH_OPTS[*]} " == *"-i"* ]]
}

@test "build_ssh_opts skips identity file when SSH_KEY is empty" {
  SSH_KEY=""
  build_ssh_opts || true
  [[ " ${SSH_OPTS[*]} " != *"-i"* ]]
}
