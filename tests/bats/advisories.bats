#!/usr/bin/env bats
# tests/bats/advisories.bats — Tests for lib/advisories.sh
#
# The evaluator is shared by every advisory check in the repository precisely
# so that they cannot disagree about what "vulnerable" means; these tests pin
# that meaning down. The patched-list clearing is the delicate part: it exists
# because upstream ranges over-report (external-secrets declares `> 0.1.0`
# vulnerable forever), but it must never clear a version whose own release
# line has an unreached fix — that is cert-manager v1.20.2 vs 1.20.3, a real
# HIGH found the day this file was written.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/log.sh"
  source "${REPO_ROOT}/lib/semver.sh"
  source "${REPO_ROOT}/lib/advisories.sh"
  FIXTURE="${BATS_TEST_TMPDIR}"
}

row() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$@"; }

# ─── advisory_rows ──────────────────────────────────────────────────────────

@test "advisory_rows emits one row per vulnerable range" {
  payload='[{"ghsa_id":"GHSA-aaaa","severity":"high","published_at":"2026-06-25T00:00:00Z",
            "summary":"s1",
            "vulnerabilities":[{"vulnerable_version_range":">= 1.18.0, <= 1.20.2","patched_versions":"1.19.6, 1.20.3"},
                               {"vulnerable_version_range":"< 1.17.9","patched_versions":"1.17.9"}]}]'
  run advisory_rows "$payload"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "GHSA-aaaa"$'\t'"high"$'\t'"2026-06-25"$'\t'">= 1.18.0, <= 1.20.2"$'\t'"1.19.6, 1.20.3"$'\t'"s1" ]]
}

@test "advisory_rows skips advisories without a range and defaults patched to ?" {
  payload='[{"ghsa_id":"GHSA-null","severity":"low","published_at":"2020-01-01T00:00:00Z",
            "summary":"no range","vulnerabilities":[{"vulnerable_version_range":null}]},
           {"ghsa_id":"GHSA-bbbb","severity":"low","published_at":"2020-01-01T00:00:00Z",
            "summary":"s","vulnerabilities":[{"vulnerable_version_range":"< 1.0.0"}]}]'
  run advisory_rows "$payload"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"GHSA-bbbb"* ]]
  [[ "${lines[0]}" == *$'\t'"?"$'\t'* ]]
}

# ─── advisory_scan: range verdicts ──────────────────────────────────────────

@test "advisory_scan flags a version inside a bracketed range" {
  rows="$(row GHSA-aaaa high 2026-06-25 '>= 1.18.0, <= 1.20.2' '1.19.6, 1.20.3' 'acme bypass')"
  run advisory_scan v1.20.2 "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GHSA-aaaa"* ]]
  [[ "$output" == *"affected by 1 range"* ]]
}

@test "advisory_scan passes a version outside every range" {
  rows="$(row GHSA-aaaa high 2026-06-25 '>= 1.18.0, <= 1.20.2' '1.19.6, 1.20.3' 'acme bypass')"
  run advisory_scan v1.20.3 "$rows"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not covered"* ]]
}

@test "advisory_scan fails on empty rows rather than reporting clean" {
  run advisory_scan v1.0.0 ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"Silence is not an absence"* ]]
}

@test "advisory_scan counts an unparsable range as a failure" {
  rows="$(row GHSA-weird low 2020-01-01 '~> 1.0' '?' 'odd operator')"
  run advisory_scan v3.0.0 "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"manual review required"* ]]
}

# ─── advisory_scan: patched-list clearing ───────────────────────────────────

@test "advisory_scan clears an in-range version released after every patch" {
  # The external-secrets case verbatim: range says vulnerable forever, the
  # patched list says fixed in 2.4.1, and v2.5.0 postdates it.
  rows="$(row GHSA-fq7h medium 2026-05-05 '> 0.1.0' '2.4.1' 'privilege escalation')"
  run advisory_scan v2.5.0 "$rows"
  [ "$status" -eq 0 ]
  [[ "$output" == *"treated as fixed"* ]]
}

@test "advisory_scan does not clear a version below its own line's patch" {
  # The cert-manager case verbatim: v1.20.2 is >= the 1.19 line's backport
  # (1.19.6) but below its own line's fix (1.20.3). Clearing it would hide a
  # live HIGH.
  rows="$(row GHSA-8rvj high 2026-06-25 '>= 1.18.0, <= 1.20.2' '1.19.6, 1.20.3' 'acme bypass')"
  run advisory_scan v1.20.2 "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" != *"treated as fixed"* ]]
}

@test "advisory_scan clears a version at exactly its line's patch" {
  rows="$(row GHSA-8rvj high 2026-06-25 '>= 1.18.0, <= 1.20.3' '1.19.6, 1.20.3' 'acme bypass')"
  run advisory_scan v1.20.3 "$rows"
  [ "$status" -eq 0 ]
}

@test "advisory_scan does not clear when the patched list is absent" {
  rows="$(row GHSA-nofix high 2026-06-25 '<= 1.20.2' '?' 'unpatched')"
  run advisory_scan v1.20.2 "$rows"
  [ "$status" -eq 1 ]
}

@test "advisory_scan clears an unparsable range through the patched list" {
  # The external-secrets GHSA-qwgc case verbatim: range is prose, patched is a
  # version any later release satisfies.
  rows="$(row GHSA-qwgc medium 2024-09-07 'master branch' 'v0.10.2' 'privilege escalation')"
  run advisory_scan v2.5.0 "$rows"
  [ "$status" -eq 0 ]
  [[ "$output" == *"treated as fixed"* ]]
}

@test "advisory_scan keeps an unparsable range unresolved when patched does not cover" {
  rows="$(row GHSA-qwgc medium 2024-09-07 'master branch' 'v0.10.2' 'privilege escalation')"
  run advisory_scan v0.9.0 "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"manual review required"* ]]
}

@test "advisory_scan does not clear on an unparsable patched list" {
  # "None" or prose in patched_versions proves nothing; the range verdict
  # must stand.
  rows="$(row GHSA-prose high 2026-06-25 '<= 1.20.2' 'see the advisory' 'prose patched field')"
  run advisory_scan v1.20.2 "$rows"
  [ "$status" -eq 1 ]
}

# ─── advisories_fetch ───────────────────────────────────────────────────────

@test "advisories_fetch reads from a file when given one" {
  echo '[{"ghsa_id":"GHSA-file"}]' > "${FIXTURE}/adv.json"
  run advisories_fetch acme/widget "${FIXTURE}/adv.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GHSA-file"* ]]
}
