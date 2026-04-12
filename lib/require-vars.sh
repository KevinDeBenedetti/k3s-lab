# shellcheck shell=bash
# lib/require-vars.sh — Validate that required environment variables are set.
#
# Usage:
#   _lib require-vars.sh
#   require_vars DOMAIN EMAIL SERVER_IP
#
# Each missing variable produces a log_error and the script exits 1.
# ──────────────────────────────────────────────────────────────────────────────

require_vars() {
  local missing=0
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      log_error "${var} is not set — add it to .env"
      missing=1
    fi
  done
  [[ "${missing}" -eq 0 ]] || exit 1
}
