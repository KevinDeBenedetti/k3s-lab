# shellcheck shell=bash
# lib/script-init.sh — One-line preamble for the k3s-lab scripts that read .env.
#
# Usage (after set -euo pipefail):
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"
#
# What it does:
#   1. Sets _RUN_REPO (the repository root) and defines _lib <name>, which
#      sources lib/<name>
#   2. Sources log.sh and load-env.sh
#   3. Loads ${_RUN_REPO}/.env as a fallback — variables already exported
#      (Taskfile, shell) take precedence
# ──────────────────────────────────────────────────────────────────────────────

_RUN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# _lib <name> — source a helper from lib/.
_lib() {
  # shellcheck disable=SC1090
  source "${_RUN_REPO}/lib/$1"
}

_lib log.sh
_lib load-env.sh

load_env "${_RUN_REPO}/.env"
