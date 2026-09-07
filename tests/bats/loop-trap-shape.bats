#!/usr/bin/env bats
# tests/bats/loop-trap-shape.bats — Tests for scripts/check-loop-trap-shape.sh
#
# Each case writes a throwaway .sh file into BATS_TEST_TMPDIR and points the
# script at that directory with --dir, so the assertions run against the
# script's real file-scanning path rather than a stubbed function.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-loop-trap-shape.sh"

setup() {
  FIX="${BATS_TEST_TMPDIR}/fixture"
  mkdir -p "$FIX"
}

run_check() { run "$SCRIPT" --dir "$FIX"; }

@test "fails on a bare [ … ] && cmd as the last statement of a for loop" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  [ "$x" = "z" ] && found=1
done
EOF
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.sh"* ]]
  [[ "$output" == *'[ "$x" = "z" ] && found=1'* ]]
}

@test "fails on the same shape with [[ … ]] and a while loop" {
  cat > "${FIX}/a.sh" <<'EOF'
while read -r line; do
  [[ "$line" = "z" ]] && found=1
done < file
EOF
  run_check
  [ "$status" -eq 1 ]
}

@test "fails on a chained &&, e.g. cond && set=1 && break" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  [ "$x" = "z" ] && found=1 && break
done
EOF
  run_check
  [ "$status" -eq 1 ]
}

@test "passes when the same condition is an if statement instead" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  if [ "$x" = "z" ]; then
    found=1
  fi
done
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "passes on an if condition that itself uses &&" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  if [ "$x" = "z" ] && [ "$x" != "a" ]; then
    found=1
  fi
done
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "passes when an || fallback is present" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  [ "$x" = "z" ] && found=1 || true
done
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "passes when the && line is not the last statement of the loop body" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  [ "$x" = "z" ] && found=1
  echo "checked $x"
done
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "passes on a bare [ … ] && cmd outside any loop" {
  cat > "${FIX}/a.sh" <<'EOF'
[ -n "${TOKEN:-}" ] && auth=(-u "x:${TOKEN}")
echo "done"
EOF
  run_check
  [ "$status" -eq 0 ]
}

@test "blank lines and comments between the trap and done are still caught" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  [ "$x" = "z" ] && found=1

  # trailing comment before the loop closes
done
EOF
  run_check
  [ "$status" -eq 1 ]
}

@test "passes on a repository with no matches at all" {
  cat > "${FIX}/a.sh" <<'EOF'
for x in a b c; do
  if [ "$x" = "z" ]; then
    found=1
  fi
done
echo "clean"
EOF
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"No loop body ends in"* ]]
}

@test "refuses to report success when no .sh files exist under --dir" {
  run "$SCRIPT" --dir "${BATS_TEST_TMPDIR}/empty"
  [ "$status" -eq 2 ]
  [[ "$output" == *"No .sh files found"* ]]
}

@test "defaults to scanning scripts/ and lib/, and this repository is clean" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
