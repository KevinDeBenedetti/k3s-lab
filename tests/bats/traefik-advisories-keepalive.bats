#!/usr/bin/env bats
# tests/bats/traefik-advisories-keepalive.bats — the job that keeps the
# scheduled Traefik advisory watch from being disabled (#128).
#
# GitHub disables a public repository's scheduled workflows after 60 days
# without repository activity: the quiet stretch in which this watch is the
# only thing still looking. The `keepalive` job re-enables the workflow on
# every run, before that can happen. Its script runs here against
# helpers/fake-gh; what GitHub does with the call cannot be checked here.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/traefik-advisories.yml"

setup() {
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  ln -s "${REPO_ROOT}/tests/bats/helpers/fake-gh" "${BIN}/gh"
  export FAKE_GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
  : >"$FAKE_GH_LOG"
}

# keepalive [<workflow file>] — run the keepalive job's steps as a runner of
# that workflow file would: each step's env set (a placeholder stands for
# every `${{ … }}` value), then its script under `bash -e`. No token leaks in
# from the developer's own environment.
keepalive() {
  local file="${1:-traefik-advisories.yml}"
  [ "$(yq '.jobs.keepalive.steps | length' "$WF")" -gt 0 ] || { echo "no keepalive job in ${WF}"; return 1; }
  # The outer parentheses matter: in mikefarah yq `,` binds looser than `|`
  # (unlike jq), so without them `.run` is read from the document root.
  yq -r '.jobs.keepalive.steps[] | (((.env // {}) | to_entries | .[] | "export " + .key + "=placeholder"), .run)' "$WF" \
    >"${BATS_TEST_TMPDIR}/job.sh"
  run env -u GH_TOKEN -u GITHUB_TOKEN PATH="${BIN}:${PATH}" \
    GITHUB_REPOSITORY=owner/repo \
    GITHUB_WORKFLOW_REF="owner/repo/.github/workflows/${file}@refs/heads/main" \
    bash -e "${BATS_TEST_TMPDIR}/job.sh"
}

@test "the keepalive re-enables the running workflow through the REST endpoint" {
  keepalive
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_GH_LOG")" = "PUT repos/owner/repo/actions/workflows/traefik-advisories.yml/enable" ]
}

@test "it re-enables the file that is running, so a rename cannot leave it behind" {
  keepalive advisories-watch.yml
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_GH_LOG")" = "PUT repos/owner/repo/actions/workflows/advisories-watch.yml/enable" ]
}

@test "only the keepalive job can write to Actions, and it can write nothing else" {
  [ "$(yq -o=json -I=0 '.jobs.keepalive.permissions' "$WF")" = '{"actions":"write"}' ]
  [ "$(yq '.permissions.actions // "unset"' "$WF")" = "unset" ]
  [ "$(yq '[.jobs[] | select(.permissions.actions == "write")] | length' "$WF")" = "1" ]
}

@test "a refused call fails the run instead of passing unnoticed" {
  export FAKE_GH_FAIL=1
  keepalive
  [ "$status" -ne 0 ]
}

@test "a failing watch does not hold the keepalive back" {
  # The watch fails its run when it finds an advisory. A keepalive waiting on
  # it would turn weeks of an open advisory into weeks without keepalive.
  [ "$(yq '.jobs.keepalive.needs // "none"' "$WF")" = "none" ]
}

@test "nothing from the repository runs with the Actions write token" {
  # No checkout and no action: only the runner's own gh.
  [ "$(yq '.jobs.keepalive.steps | length' "$WF")" -gt 0 ]
  [ "$(yq '[.jobs.keepalive.steps[] | select(has("uses"))] | length' "$WF")" = "0" ]
}
