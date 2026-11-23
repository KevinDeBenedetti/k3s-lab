#!/bin/bash
set -euo pipefail

# =============================================================================
# ssh-node.sh — Open an SSH shell on a cluster node
#
# Called by: task ssh:server / task ssh:agent.
# Usage:     scripts/ssh-node.sh <host> [ssh args…]
#
# Optional env (from .env):
#   SSH_USER   default: your local $USER (as ssh itself, and get-kubeconfig.sh)
#   SSH_PORT   default: 22
#   SSH_KEY    identity file; left out when unset, so ssh uses its own defaults
#   SSH        ssh command (default: ssh) — the test seam
#
# Host keys: accept-new — a new node is trusted on first contact, a changed key
# is refused. After a node rebuild: task ssh:known-hosts-reset
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib ssh-opts.sh

host="${1:-}"
if [[ -z "$host" ]]; then
  log_error "Usage: $(basename "$0") <host> — the node's host (SERVER_IP or AGENT_IP is not set?)"
  exit 2
fi
shift

build_ssh_opts "${SSH_PORT:-22}" accept-new
exec "${SSH:-ssh}" "${SSH_OPTS[@]}" "$@" "${SSH_USER:-${USER}}@${host}"
