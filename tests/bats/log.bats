#!/usr/bin/env bats
# tests/bats/log.bats — Unit tests for lib/log.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/log.sh"
}

@test "log_info outputs [info] prefix" {
  run log_info "hello world"
  [[ "$output" == *"[info]"*"hello world"* ]]
}

@test "log_ok outputs checkmark" {
  run log_ok "success message"
  [[ "$output" == *"success message"* ]]
}

@test "log_warn outputs warning" {
  run log_warn "something is off"
  [[ "$output" == *"something is off"* ]]
}

@test "log_error outputs error message" {
  run log_error "something broke"
  [[ "$output" == *"something broke"* ]]
}

@test "log_step outputs step label" {
  run log_step "Installing packages"
  [[ "$output" == *"Installing packages"* ]]
}
