#!/usr/bin/env bash
# common-setup.bash — loaded by all bats test files via: load 'common-setup'

_common_setup() {
    # BATS_TEST_FILENAME points to the .bats file being executed
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." >/dev/null 2>&1 && pwd)"
}
