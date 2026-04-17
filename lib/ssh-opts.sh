# shellcheck shell=bash
# lib/ssh-opts.sh — Build the SSH_OPTS array from environment variables.
# Source this file, then call: build_ssh_opts [port] [StrictHostKeyChecking] [ConnectTimeout]
#
# Reads:   SSH_KEY  (optional — path to identity file; skipped if empty)
# Sets:    SSH_OPTS (global array, ready to expand as "${SSH_OPTS[@]}")
#
# Examples:
#   build_ssh_opts                          # port=22, accept-new, no timeout
#   build_ssh_opts "${_SSH_PORT}" accept-new 15
#   build_ssh_opts "${SSH_PORT}"  no        # StrictHostKeyChecking=no, no timeout

build_ssh_opts() {
  local port="${1:-${SSH_PORT:-22}}"
  local strict="${2:-accept-new}"
  local timeout="${3:-0}"

  SSH_OPTS=(-p "${port}" -o "StrictHostKeyChecking=${strict}")
  [[ "${timeout}" -gt 0 ]] && SSH_OPTS+=(-o "ConnectTimeout=${timeout}")
  [[ -n "${SSH_KEY:-}" ]]  && SSH_OPTS+=(-i "${SSH_KEY}")
}
