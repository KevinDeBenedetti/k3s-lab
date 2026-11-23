#!/usr/bin/env bats
# tests/bats/release-charts-guard.bats — who may start a chart release.
#
# release-charts.yml publishes, with `packages: write`, every chart version not
# yet on GHCR, first writer wins. A manual run from any branch could therefore
# take the next version number with unreviewed charts, and main's real release
# of that version would then be skipped (#127). GitHub expressions cannot be
# evaluated here, so this pins the shape of the job's guard.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/release-charts.yml"

guard() { yq -r '.jobs.release.if' "$WF" | tr -s ' \n' ' '; }

@test "a manual run publishes only from main" {
  [[ "$(guard)" == *"github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'"* ]]
}

@test "a manual run is never allowed on its own, whatever the branch" {
  # The unguarded form: `github.event_name == 'workflow_dispatch' ||`
  [[ "$(guard)" != *"github.event_name == 'workflow_dispatch' ||"* ]]
}

@test "the automatic path still requires a successful CI run of a push" {
  [[ "$(guard)" == *"github.event.workflow_run.conclusion == 'success'"* ]]
  [[ "$(guard)" == *"github.event.workflow_run.event == 'push'"* ]]
}
