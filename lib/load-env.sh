# shellcheck shell=bash
# lib/load-env.sh — Load a .env file without overwriting already-set variables.
# Source this file, then call: load_env [path/to/.env]
#
# This lets Task targets (or the environment) override .env values at call time.
# Any variable already exported in the environment is left untouched.
#
# Handles: `export KEY=value` prefixes, surrounding single/double quotes,
# blank lines and full-line comments. Values may contain `=`.
#
# Usage:
#   source "${SCRIPT_DIR}/../lib/load-env.sh"
#   load_env "${INFRA_ROOT}/.env"   # explicit path
#   load_env                        # falls back to ${INFRA_ROOT}/.env if set

load_env() {
  local env_file="${1:-${INFRA_ROOT:+${INFRA_ROOT}/.env}}"
  [[ -n "${env_file}" && -f "${env_file}" ]] || return 0
  local key value
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${key// /}" ]]          && continue
    key="${key#"${key%%[![:space:]]*}"}"   # ltrim
    key="${key#export }"                   # allow `export KEY=value`
    key="${key// /}"
    # Strip matching surrounding quotes — `KEY="value"` / `KEY='value'`
    # (plain Helm/.env style files quote values; the quotes are not data).
    if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
      value="${value#\"}"; value="${value%\"}"
    elif [[ "$value" == \'*\' && ${#value} -ge 2 ]]; then
      value="${value#\'}"; value="${value%\'}"
    fi
    [[ -n "${!key+defined}" ]] || export "${key}=${value}"
  done < "${env_file}"
  return 0
}
