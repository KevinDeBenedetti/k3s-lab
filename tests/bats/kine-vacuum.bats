#!/usr/bin/env bats
# tests/bats/kine-vacuum.bats — ansible/roles/k3s_server/templates/kine-vacuum.sh.j2,
# rendered and run against fakes of the node's tools (systemctl, sqlite3, stat,
# numfmt, df, k3s). The script stops k3s on a schedule nobody watches: the
# property that matters is that k3s is running again whatever goes wrong (#123).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
TEMPLATE="${REPO_ROOT}/ansible/roles/k3s_server/templates/kine-vacuum.sh.j2"

setup() {
  DB_DIR="${BATS_TEST_TMPDIR}/db"
  BIN="${BATS_TEST_TMPDIR}/bin"
  export CALLS="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "$DB_DIR" "$BIN"
  printf 'live data\n' >"${DB_DIR}/state.db"

  # Render the Jinja variables the role passes (defaults/main.yml).
  SCRIPT="${BATS_TEST_TMPDIR}/kine-vacuum.sh"
  sed -e "s|{{ kine_vacuum_db_dir }}|${DB_DIR}|" \
      -e "s|{{ kine_vacuum_threshold_bytes }}|5|" \
      -e "s|{{ kine_vacuum_k3s_service }}|k3s.service|" \
      "$TEMPLATE" >"$SCRIPT"
  chmod +x "$SCRIPT"

  fake systemctl 'echo "systemctl $*" >>"$CALLS"; [[ "$1" != is-active ]] || [[ -f "$BIN/.started" ]]; [[ "$1" != start ]] || touch "$BIN/.started"'
  fake stat      'wc -c <"${!#}" | tr -d " "'
  fake numfmt    'echo "${!#}B"'
  fake df        'printf "Avail\n%s\n" "${FAKE_DF_AVAIL:-1000000000}"'
  fake k3s       'exit 0'
  fake sleep     'exit 0'
  # sqlite3 <db> <sql>: VACUUM INTO writes a smaller copy, unless told to fail.
  fake sqlite3   'echo "sqlite3 $2" >>"$CALLS"
    if [[ "$2" == VACUUM* ]]; then
      [[ -z "${FAKE_SQLITE_FAIL:-}" ]] || { echo "Error: database or disk is full" >&2; exit 13; }
      out=$(printf "%s" "$2" | awk -F"\047" "{ print \$2 }")   # the quoted path
      printf "live\n" >"$out"
    fi'
  export PATH="${BIN}:${PATH}"
}

# fake <name> <body> — a stub on PATH.
fake() {
  printf '#!/usr/bin/env bash\nBIN=%q\n%s\n' "$BIN" "$2" >"${BIN}/$1"
  chmod +x "${BIN}/$1"
}

# count <pattern> — calls matching it (0 when nothing was called at all).
count() { [[ -f "$CALLS" ]] || { echo 0; return; }; grep -c "$1" "$CALLS" || true; }
started() { count '^systemctl start k3s.service'; }
stopped() { count '^systemctl stop k3s.service'; }

@test "a successful run compacts the database and starts k3s again, once" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "${DB_DIR}/state.db")" = "live" ]
  [ ! -e "${DB_DIR}/state.db.pre-vacuum" ]
  [ "$(stopped)" -eq 1 ]
  [ "$(started)" -eq 1 ]
}

@test "a failing VACUUM starts k3s again and leaves the database untouched" {
  FAKE_SQLITE_FAIL=1 run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ "$(started)" -eq 1 ]
  [ "$(cat "${DB_DIR}/state.db")" = "live data" ]
  [ -z "$(ls "$DB_DIR" | grep compacting || true)" ]
}

@test "a failure between the two moves puts the original database back" {
  # The second mv (compacted copy → state.db) fails: state.db must not be left
  # missing when k3s starts again.
  fake mv 'if [[ "$1" == *compacting* ]]; then echo "mv: cannot move" >&2; exit 1; fi; /bin/mv "$@"'
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ "$(cat "${DB_DIR}/state.db")" = "live data" ]
  [ "$(started)" -eq 1 ]
}

@test "too little free space for the compacted copy: k3s is never stopped" {
  FAKE_DF_AVAIL=3 run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"free"* ]]
  [ "$(stopped)" -eq 0 ]
}

@test "a database below the threshold is left alone and k3s keeps running" {
  printf 'tiny' >"${DB_DIR}/state.db"
  sed -i.bak "s|^THRESHOLD_BYTES=.*|THRESHOLD_BYTES=\"1000\"|" "$SCRIPT"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(stopped)" -eq 0 ]
}
