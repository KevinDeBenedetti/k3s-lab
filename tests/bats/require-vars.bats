#!/usr/bin/env bats
# tests/bats/require-vars.bats — Unit tests for lib/require-vars.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/log.sh"
  source "${REPO_ROOT}/lib/require-vars.sh"
}

@test "require_vars passes when all variables are set" {
  MY_VAR="value"
  run require_vars MY_VAR
  [ "$status" -eq 0 ]
}

@test "require_vars fails when a variable is unset" {
  unset MISSING_VAR
  run require_vars MISSING_VAR
  [ "$status" -eq 1 ]
}

@test "require_vars fails when a variable is empty" {
  EMPTY_VAR=""
  run require_vars EMPTY_VAR
  [ "$status" -eq 1 ]
}

@test "require_vars checks multiple variables and fails on missing" {
  FIRST_VAR="set"
  unset SECOND_VAR
  run require_vars FIRST_VAR SECOND_VAR
  [ "$status" -eq 1 ]
}

@test "require_vars passes when multiple variables are all set" {
  FOO="a"
  BAR="b"
  run require_vars FOO BAR
  [ "$status" -eq 0 ]
}
