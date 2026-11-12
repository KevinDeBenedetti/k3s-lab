#!/usr/bin/env bats
# tests/bats/script-init.bats — Unit tests for lib/script-init.sh
#
# The point under test: when k3s-lab is consumed from a pinned checkout, its
# scripts must read the .env of the repository that runs them (the current
# directory), not one sitting inside the checkout.
#
# Each test sources script-init.sh from a COPY of lib/ under a fake checkout,
# so the real repository's .env is never read.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  CHECKOUT="${BATS_TEST_TMPDIR}/k3s-lab"
  PROJECT="${BATS_TEST_TMPDIR}/config-repo"
  mkdir -p "${CHECKOUT}/lib" "${CHECKOUT}/scripts" "${PROJECT}"
  cp "${REPO_ROOT}"/lib/*.sh "${CHECKOUT}/lib/"
  # A script shaped like the real ones: it sources script-init.sh relative to
  # itself, then prints the variable under test.
  cat > "${CHECKOUT}/scripts/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"
printf '%s|%s\n' "${SI_VALUE:-unset}" "${K3S_LAB_PROJECT_DIR}"
PROBE
  chmod +x "${CHECKOUT}/scripts/probe.sh"
  unset SI_VALUE K3S_LAB_ENV_FILE K3S_LAB_PROJECT_DIR
}

@test "script-init loads the .env of the current directory, not the checkout's" {
  echo "SI_VALUE=project" > "${PROJECT}/.env"
  echo "SI_VALUE=checkout" > "${CHECKOUT}/.env"
  cd "$PROJECT"
  run "${CHECKOUT}/scripts/probe.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "project|${PROJECT}" ]
}

@test "script-init falls back to the checkout's .env when the project has none" {
  echo "SI_VALUE=checkout" > "${CHECKOUT}/.env"
  cd "$PROJECT"
  run "${CHECKOUT}/scripts/probe.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "checkout|${PROJECT}" ]
}

@test "script-init loads only one file — no mixing of project and checkout values" {
  echo "OTHER=1" > "${PROJECT}/.env"
  echo "SI_VALUE=checkout" > "${CHECKOUT}/.env"
  cd "$PROJECT"
  run "${CHECKOUT}/scripts/probe.sh"
  [ "$output" = "unset|${PROJECT}" ]
}

@test "K3S_LAB_ENV_FILE wins over the project's .env" {
  echo "SI_VALUE=project" > "${PROJECT}/.env"
  echo "SI_VALUE=explicit" > "${BATS_TEST_TMPDIR}/cluster.env"
  cd "$PROJECT"
  K3S_LAB_ENV_FILE="${BATS_TEST_TMPDIR}/cluster.env" run "${CHECKOUT}/scripts/probe.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "explicit|${PROJECT}" ]
}

@test "K3S_LAB_ENV_FILE pointing at a missing file is an error" {
  cd "$PROJECT"
  K3S_LAB_ENV_FILE="${BATS_TEST_TMPDIR}/nope.env" run "${CHECKOUT}/scripts/probe.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"K3S_LAB_ENV_FILE points at a missing file"* ]]
}

@test "K3S_LAB_PROJECT_DIR overrides the current directory" {
  other="${BATS_TEST_TMPDIR}/elsewhere"
  mkdir -p "$other"
  echo "SI_VALUE=elsewhere" > "${other}/.env"
  cd "$PROJECT"
  K3S_LAB_PROJECT_DIR="$other" run "${CHECKOUT}/scripts/probe.sh"
  [ "$output" = "elsewhere|${other}" ]
}

@test "an exported variable beats every .env" {
  echo "SI_VALUE=project" > "${PROJECT}/.env"
  cd "$PROJECT"
  SI_VALUE=shell run "${CHECKOUT}/scripts/probe.sh"
  [ "$output" = "shell|${PROJECT}" ]
}
