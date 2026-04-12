# shellcheck shell=bash
# lib/script-init.sh — One-line preamble for all k3s-lab deploy scripts.
#
# Usage (after set -euo pipefail):
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"
#
# Or in remote/pipe mode (when BASH_SOURCE is /dev/fd/*):
#   source <(curl -fsSL "${K3S_LAB_RAW}/lib/script-init.sh")
#
# What it does:
#   1. Detects LOCAL vs REMOTE execution mode (via run-mode.sh)
#   2. Sources log.sh and load-env.sh
#   3. Loads .env (fallback — vars from Make take precedence)
# ──────────────────────────────────────────────────────────────────────────────

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"

# Detect caller context — [1] is the script that sourced us
_run_src="${BASH_SOURCE[1]:-}"
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  source "$(cd "$(dirname "${_run_src}")" && pwd)/../lib/run-mode.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW}/lib/run-mode.sh")
fi

_lib log.sh
_lib load-env.sh

load_env "${_RUN_REPO:-.}/.env"
