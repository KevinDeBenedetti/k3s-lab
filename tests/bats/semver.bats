#!/usr/bin/env bats
# tests/bats/semver.bats — Unit tests for lib/semver.sh
#
# The ranges used here are the `vulnerable_version_range` values actually
# published by the GitHub API for traefik/traefik (captured on 2026-07-30):
# these are the ones the advisory watch must be able to evaluate.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/semver.sh"
}

# ─── semver_cmp ─────────────────────────────────────────────────────────────

@test "semver_cmp orders equal versions as 0" {
  run semver_cmp v3.7.9 v3.7.9
  [ "$output" = "0" ]
}

@test "semver_cmp tolerates a missing v prefix on either side" {
  run semver_cmp 3.7.9 v3.7.9
  [ "$output" = "0" ]
  run semver_cmp v3.7.9 3.7.9
  [ "$output" = "0" ]
}

@test "semver_cmp compares patch numerically, not lexicographically" {
  run semver_cmp v3.7.9 v3.7.8
  [ "$output" = "1" ]
  run semver_cmp v3.7.9 v3.7.10
  [ "$output" = "-1" ]
}

@test "semver_cmp compares minor before patch" {
  run semver_cmp v3.6.24 v3.7.0
  [ "$output" = "-1" ]
}

@test "semver_cmp compares major before minor" {
  run semver_cmp v2.11.52 v3.0.0
  [ "$output" = "-1" ]
}

@test "semver_cmp treats missing fields as zero" {
  run semver_cmp v3.7 v3.7.0
  [ "$output" = "0" ]
}

@test "semver_cmp truncates pre-release suffixes" {
  run semver_cmp v3.7.0-rc.1 v3.7.0
  [ "$output" = "0" ]
}

# ─── semver_in_range: real traefik/traefik ranges ───────────────────────────

@test "semver_in_range: v3.7.8 is caught by GHSA-3ccp (<= v3.7.8)" {
  run semver_in_range v3.7.8 '<= v3.7.8'
  [ "$status" -eq 0 ]
}

@test "semver_in_range: v3.7.9 escapes GHSA-3ccp (<= v3.7.8)" {
  run semver_in_range v3.7.9 '<= v3.7.8'
  [ "$status" -eq 1 ]
}

@test "semver_in_range: v3.7.6 is caught by GHSA-cxjq (>= v3.7.0, <= v3.7.6)" {
  run semver_in_range v3.7.6 '>= v3.7.0, <= v3.7.6'
  [ "$status" -eq 0 ]
}

@test "semver_in_range: v3.7.7 escapes GHSA-cxjq's 3.7 range" {
  run semver_in_range v3.7.7 '>= v3.7.0, <= v3.7.6'
  [ "$status" -eq 1 ]
}

@test "semver_in_range: a 3.7 pin is not matched by a 2.11 range" {
  run semver_in_range v3.7.9 '<= v2.11.52'
  [ "$status" -eq 1 ]
}

@test "semver_in_range: a 3.7 pin is not matched by a 3.6 range" {
  run semver_in_range v3.7.9 '>= v3.6.0, <= v3.6.22'
  [ "$status" -eq 1 ]
}

@test "semver_in_range: below the lower bound is outside the range" {
  run semver_in_range v3.6.9 '>= v3.7.0, <= v3.7.7'
  [ "$status" -eq 1 ]
}

# ─── semver_in_range: operators ─────────────────────────────────────────────

@test "semver_in_range handles strict < and >" {
  run semver_in_range v3.7.8 '< v3.7.9'
  [ "$status" -eq 0 ]
  run semver_in_range v3.7.9 '< v3.7.9'
  [ "$status" -eq 1 ]
  run semver_in_range v3.7.9 '> v3.7.8'
  [ "$status" -eq 0 ]
}

@test "semver_in_range treats a bare version as an equality" {
  run semver_in_range v3.7.9 'v3.7.9'
  [ "$status" -eq 0 ]
  run semver_in_range v3.7.8 'v3.7.9'
  [ "$status" -eq 1 ]
}

@test "semver_in_range does not mistake <= for <" {
  run semver_in_range v3.7.8 '<= v3.7.8'
  [ "$status" -eq 0 ]
  run semver_in_range v3.7.8 '< v3.7.8'
  [ "$status" -eq 1 ]
}

@test "semver_in_range tolerates missing spaces around operators" {
  run semver_in_range v3.7.8 '<=v3.7.8'
  [ "$status" -eq 0 ]
}

# ─── semver_in_range: comma lists that cannot mean AND ──────────────────────
# Both forms were found as-published on components we deploy (cert-manager
# GHSA-gx3x-vq4p-mhhv and GHSA-r4pg-vg54-wxx4). Read as AND they can only
# under-report — the exact failure mode these checks exist to prevent.

@test "semver_in_range reads a list of exact versions as an enumeration" {
  # AND of two different `=` is always false; a version in the list must match…
  run semver_in_range v1.18.1 'v1.18.0,v1.18.1,v1.19.0'
  [ "$status" -eq 0 ]
  # …and one outside it must not.
  run semver_in_range v1.20.2 'v1.18.0,v1.18.1,v1.19.0'
  [ "$status" -eq 1 ]
}

@test "semver_in_range reads uniform upper bounds as per-line ceilings" {
  # `<v1.12.14,<v1.15.4,<v1.16.2` is one ceiling per backported release line.
  # v1.15.3 is not < v1.12.14, so the AND reading calls it clean — it is
  # vulnerable on its own line.
  run semver_in_range v1.15.3 '<v1.12.14,<v1.15.4,<v1.16.2'
  [ "$status" -eq 0 ]
  # Above every ceiling stays clean.
  run semver_in_range v1.20.2 '<v1.12.14,<v1.15.4,<v1.16.2'
  [ "$status" -eq 1 ]
}

@test "semver_in_range keeps AND for mixed-direction intervals" {
  # The documented GitHub form: a bracket. OR would swallow everything below
  # the ceiling, including versions under the floor.
  run semver_in_range v1.17.9 '>= 1.18.0, <= 1.20.2'
  [ "$status" -eq 1 ]
  run semver_in_range v1.20.2 '>= 1.18.0, <= 1.20.2'
  [ "$status" -eq 0 ]
}

# ─── semver_in_range: refusing to guess at the unparsable ───────────────────

@test "semver_in_range returns 2 on an unknown operator rather than 'not vulnerable'" {
  run semver_in_range v3.7.9 '~> v3.7.0'
  [ "$status" -eq 2 ]
}

@test "semver_in_range returns 2 on an empty range" {
  run semver_in_range v3.7.9 ''
  [ "$status" -eq 2 ]
}

# ─── semver_latest ──────────────────────────────────────────────────────────

@test "semver_latest picks the highest version regardless of input order" {
  run bash -c 'source "'"${REPO_ROOT}"'/lib/semver.sh"; printf "0.14.0\n0.15.0\n0.12.0\n" | semver_latest'
  [ "$output" = "0.15.0" ]
}

@test "semver_latest compares numerically, not lexically" {
  # The case a `sort` would get wrong: 0.9.0 sorts after 0.15.0 as text.
  run bash -c 'source "'"${REPO_ROOT}"'/lib/semver.sh"; printf "0.9.0\n0.15.0\n" | semver_latest'
  [ "$output" = "0.15.0" ]
}

@test "semver_latest ignores floating registry tags" {
  # A registry also serves `latest`/`stable`; ordering those against real
  # versions is meaningless, so they must not win.
  run bash -c 'source "'"${REPO_ROOT}"'/lib/semver.sh"; printf "latest\n0.15.0\nstable\n" | semver_latest'
  [ "$output" = "0.15.0" ]
}

@test "semver_latest ignores pre-releases" {
  # semver_cmp truncates the suffix, so v1.0.0-rc.1 would tie with v1.0.0 and
  # could be reported as the newest published release when it is not one.
  run bash -c 'source "'"${REPO_ROOT}"'/lib/semver.sh"; printf "1.0.0-rc.1\n0.15.0\n" | semver_latest'
  [ "$output" = "0.15.0" ]
}

@test "semver_latest keeps the v prefix it was given" {
  run bash -c 'source "'"${REPO_ROOT}"'/lib/semver.sh"; printf "v3.7.8\nv3.7.9\n" | semver_latest'
  [ "$output" = "v3.7.9" ]
}

@test "semver_latest prints nothing when no input is release-shaped" {
  # Callers must fail on this silence, not read it as "nothing newer exists".
  run bash -c 'source "'"${REPO_ROOT}"'/lib/semver.sh"; printf "latest\n\n" | semver_latest'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
