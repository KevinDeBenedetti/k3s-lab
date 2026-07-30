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

# ─── semver_in_range: refusing to guess at the unparsable ───────────────────

@test "semver_in_range returns 2 on an unknown operator rather than 'not vulnerable'" {
  run semver_in_range v3.7.9 '~> v3.7.0'
  [ "$status" -eq 2 ]
}

@test "semver_in_range returns 2 on an empty range" {
  run semver_in_range v3.7.9 ''
  [ "$status" -eq 2 ]
}
