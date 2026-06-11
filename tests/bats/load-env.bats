#!/usr/bin/env bats
# tests/bats/load-env.bats — Unit tests for lib/load-env.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/load-env.sh"
  ENV_FILE="${BATS_TEST_TMPDIR}/.env"
}

@test "load_env loads a simple KEY=value pair" {
  echo "LE_SIMPLE=hello" > "$ENV_FILE"
  unset LE_SIMPLE
  load_env "$ENV_FILE"
  [ "$LE_SIMPLE" = "hello" ]
}

@test "load_env does not overwrite an already-set variable" {
  echo "LE_KEEP=fromfile" > "$ENV_FILE"
  export LE_KEEP="fromenv"
  load_env "$ENV_FILE"
  [ "$LE_KEEP" = "fromenv" ]
}

@test "load_env preserves an empty pre-set variable" {
  echo "LE_EMPTY=fromfile" > "$ENV_FILE"
  export LE_EMPTY=""
  load_env "$ENV_FILE"
  [ "$LE_EMPTY" = "" ]
}

@test "load_env strips double quotes around values" {
  echo 'LE_DQ="quoted value"' > "$ENV_FILE"
  unset LE_DQ
  load_env "$ENV_FILE"
  [ "$LE_DQ" = "quoted value" ]
}

@test "load_env strips single quotes around values" {
  echo "LE_SQ='quoted value'" > "$ENV_FILE"
  unset LE_SQ
  load_env "$ENV_FILE"
  [ "$LE_SQ" = "quoted value" ]
}

@test "load_env keeps inner quotes intact" {
  echo 'LE_INNER=ab"cd' > "$ENV_FILE"
  unset LE_INNER
  load_env "$ENV_FILE"
  [ "$LE_INNER" = 'ab"cd' ]
}

@test "load_env handles export prefix" {
  echo "export LE_EXPORTED=value" > "$ENV_FILE"
  unset LE_EXPORTED
  load_env "$ENV_FILE"
  [ "$LE_EXPORTED" = "value" ]
}

@test "load_env keeps equals signs inside values" {
  echo "LE_URL=postgres://u:p@host/db?sslmode=require" > "$ENV_FILE"
  unset LE_URL
  load_env "$ENV_FILE"
  [ "$LE_URL" = "postgres://u:p@host/db?sslmode=require" ]
}

@test "load_env skips comments and blank lines" {
  printf '# a comment\n\nLE_AFTER=ok\n' > "$ENV_FILE"
  unset LE_AFTER
  load_env "$ENV_FILE"
  [ "$LE_AFTER" = "ok" ]
}

@test "load_env handles a file without trailing newline" {
  printf 'LE_NONL=last' > "$ENV_FILE"
  unset LE_NONL
  load_env "$ENV_FILE"
  [ "$LE_NONL" = "last" ]
}

@test "load_env returns 0 when the file does not exist" {
  run load_env "${BATS_TEST_TMPDIR}/does-not-exist.env"
  [ "$status" -eq 0 ]
}

@test "load_env returns 0 when called without argument and INFRA_ROOT unset" {
  unset INFRA_ROOT
  run load_env
  [ "$status" -eq 0 ]
}
