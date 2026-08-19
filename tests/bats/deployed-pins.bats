#!/usr/bin/env bats
# tests/bats/deployed-pins.bats — Tests for scripts/check-deployed-pins.sh
#
# Why this file exists: the script shipped a bug that made it die SILENTLY, and
# it did so precisely when the thing it watches was healthy.
#
# Inside the `newer=` command substitution, the loop body ended with
# `[ … ] && printf`. On any tag that is NOT newer than the pin that body exits
# non-zero; the `while` inherits the last body's status, `set -o pipefail`
# propagates it through the pipeline, and `set -e` then kills the whole script on
# the assignment — printing nothing. The log stops after the header, the exit
# code is 1, and the calling workflow files that as "the pins have drifted".
#
# The trigger is the cruel part: it fires when NO tag is newer, i.e. once a pin
# catches up to the newest published release. A drift watcher broke exactly when
# the drift was fixed, and reported it as drift. That was issue #76, whose
# section 3 is a bare header with no verdict.
#
# The registry is stubbed with a fake `curl` on PATH, so these run offline.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-deployed-pins.sh"

setup() {
  APPSET="${BATS_TEST_TMPDIR}/platform.yaml"
  cat > "$APPSET" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform
spec:
  generators:
    - list:
        elements:
          - name: security
            chart: platform-security
            version: "0.19.0"
  template:
    spec:
      sources:
        - repoURL: 'ghcr.io/kevindebenedetti/charts'
          chart: '{{ .chart }}'
          targetRevision: '{{ .version }}'
EOF

  TAGS='["0.18.3","0.18.4","0.19.0"]'
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  cat > "${BIN}/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    *"/token?"*)      echo '{"token":"stub"}'; exit 0 ;;
    *"/tags/list"*)   echo '{"tags":${TAGS}}'; exit 0 ;;
    *"/manifests/"*)  echo '{}'; exit 0 ;;
  esac
done
exit 0
EOF
  chmod +x "${BIN}/curl"
  PATH="${BIN}:${PATH}"
  export PATH
}

run_check() { run "$SCRIPT" --applicationset "$APPSET" "$@"; }

@test "a pin sitting on the newest published release does not kill the script" {
  # The regression. Before the fix this exited 1 having printed only the header.
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest published"* ]]
}

@test "the run reaches its verdict instead of stopping after the header" {
  run_check
  [[ "$output" == *"pin(s) checked"* ]]
}

@test "a pin one release behind is reported without failing the threshold" {
  sed -i.bak 's/version: "0.19.0"/version: "0.18.4"/' "$APPSET"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 behind"* ]]
  [[ "$output" == *"pin(s) checked"* ]]
}

@test "a pin past the threshold fails" {
  sed -i.bak 's/version: "0.19.0"/version: "0.18.3"/' "$APPSET"
  run_check --max-behind 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"pin(s) checked"* ]]
}

@test "a pin ahead of the registry is reported as unresolvable" {
  sed -i.bak 's/version: "0.19.0"/version: "0.99.0"/' "$APPSET"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolvable"* ]]
}

@test "an unreadable registry is a warning with a verdict, not a silent death" {
  cat > "${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 22
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  run_check
  [[ "$output" == *"could not list tags"* ]]
  [[ "$output" == *"pin(s) checked"* ]]
}

@test "an ApplicationSet pinning nothing is refused rather than passed" {
  printf 'kind: ApplicationSet\n' > "$APPSET"
  run_check
  [ "$status" -eq 1 ]
}
