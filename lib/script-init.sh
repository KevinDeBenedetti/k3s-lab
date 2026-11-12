# shellcheck shell=bash
# lib/script-init.sh — One-line preamble for the k3s-lab scripts that read .env.
#
# Usage (after set -euo pipefail):
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"
#
# What it does:
#   1. Sets _RUN_REPO (this k3s-lab checkout) and defines _lib <name>, which
#      sources lib/<name>
#   2. Sets K3S_LAB_PROJECT_DIR, the repository that OPERATES the cluster —
#      the one holding .env, the inventory and the Terraform state. It defaults
#      to the current directory: a config repo that includes k3s-lab's
#      taskfiles (or calls its scripts from a pinned checkout) runs them from
#      its own root, so its files are found there, not inside the checkout.
#   3. Sources log.sh and load-env.sh, then loads ONE .env file, first match:
#        $K3S_LAB_ENV_FILE                explicit path (must exist)
#        $K3S_LAB_PROJECT_DIR/.env        the operating repo
#        $_RUN_REPO/.env                  k3s-lab used standalone
#      Variables already exported (Taskfile, shell) always take precedence.
# ──────────────────────────────────────────────────────────────────────────────

_RUN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K3S_LAB_PROJECT_DIR="${K3S_LAB_PROJECT_DIR:-$PWD}"

# _lib <name> — source a helper from lib/.
_lib() {
  # shellcheck disable=SC1090
  source "${_RUN_REPO}/lib/$1"
}

_lib log.sh
_lib load-env.sh

# _script_env_file — print the .env file this run should load (may not exist).
_script_env_file() {
  if [[ -n "${K3S_LAB_ENV_FILE:-}" ]]; then
    printf '%s\n' "$K3S_LAB_ENV_FILE"
  elif [[ -f "${K3S_LAB_PROJECT_DIR}/.env" ]]; then
    printf '%s\n' "${K3S_LAB_PROJECT_DIR}/.env"
  else
    printf '%s\n' "${_RUN_REPO}/.env"
  fi
}

if [[ -n "${K3S_LAB_ENV_FILE:-}" && ! -f "${K3S_LAB_ENV_FILE}" ]]; then
  log_error "K3S_LAB_ENV_FILE points at a missing file: ${K3S_LAB_ENV_FILE}"
  exit 1
fi

load_env "$(_script_env_file)"
