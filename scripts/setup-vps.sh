#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-vps.sh — Bootstrap a fresh Debian VPS with dotfiles
# Run FROM YOUR LOCAL MACHINE.
#
# Usage: ./scripts/setup-vps.sh <VPS_IP> [SSH_USER] [SSH_PORT] [INITIAL_USER]
# =============================================================================

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"

# setup-vps uses positional args — keep manual preamble (no .env load needed)
_run_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  source "$(cd "$(dirname "${_run_src}")" && pwd)/../lib/run-mode.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW}/lib/run-mode.sh")
fi

_lib log.sh
_lib ssh-opts.sh

VPS_IP="${1:?'Usage: ./scripts/setup-vps.sh <VPS_IP> [SSH_USER] [SSH_PORT] [INITIAL_USER]'}"
SSH_USER="${2:-${SSH_USER:-kevin}}"
_SSH_PORT="${3:-${SSH_PORT:-22}}"
INITIAL_USER="${4:-${INITIAL_USER:-root}}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_ed25519}"
DOTFILES_FLAGS="${DOTFILES_FLAGS:--a}"

# Append -u USER to dotfiles flags when provisioning a non-root user.
# setup-user.sh (in dotfiles) will create the user, copy SSH keys, and
# optionally grant NOPASSWD sudo — all before the security step disables root login.
if [[ "${SSH_USER}" != "root" ]]; then
  DOTFILES_FLAGS="${DOTFILES_FLAGS} -u ${SSH_USER}"
fi

DOTFILES_URL="https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh"

# SSH_ALLOWED_USERS defaults to SSH_USER so sshd AllowUsers is always set
SSH_ALLOWED_USERS="${SSH_ALLOWED_USERS:-${SSH_USER}}"

log_info "Bootstrapping VPS ${VPS_IP} as ${INITIAL_USER} → ${SSH_USER} (port ${_SSH_PORT})..."

build_ssh_opts "${_SSH_PORT}" "accept-new" 15

# ─────────────────────────────────────────────────────────────────────────────
# Step 0: Remove stale known_hosts entry (expected after VPS reformat)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Clearing stale host key for ${VPS_IP} from known_hosts..."
ssh-keygen -R "${VPS_IP}" 2>/dev/null || true
_RESOLVED=$(ssh-keyscan -t ed25519 -p "${_SSH_PORT}" "${VPS_IP}" 2>/dev/null | awk '{print $1}') || true
[[ -n "${_RESOLVED}" && "${_RESOLVED}" != "${VPS_IP}" ]] && ssh-keygen -R "${_RESOLVED}" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Install prerequisites
# ─────────────────────────────────────────────────────────────────────────────
log_step "Installing prerequisites (curl) on ${VPS_IP}..."
ssh "${SSH_OPTS[@]}" "${INITIAL_USER}@${VPS_IP}" \
  "export LC_ALL=C; apt-get update -qq && apt-get install -y -qq curl"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Run dotfiles bootstrap
# init.sh -u ${SSH_USER}   → creates the user + copies root SSH key + NOPASSWD
# This runs BEFORE sshd hardening (PermitRootLogin no), so the flow is:
#   prereqs → create user → kubernetes profile → security → copy dotfiles
# ─────────────────────────────────────────────────────────────────────────────
REMOTE_EXPORTS="export LC_ALL=C"
REMOTE_EXPORTS+="; export SSH_ALLOWED_USERS='${SSH_ALLOWED_USERS}'"
REMOTE_EXPORTS+="; export SSH_NOPASSWD=true"
REMOTE_EXPORTS+="; export COPY_ROOT_SSH_KEY=true"
if [[ -n "${SSH_PORT:-}" && "${SSH_PORT}" != "22" ]]; then
  REMOTE_EXPORTS+="; export SSH_PORT=${SSH_PORT}"
fi

log_step "Running dotfiles bootstrap (flags: ${DOTFILES_FLAGS})..."
ssh "${SSH_OPTS[@]}" \
  "${INITIAL_USER}@${VPS_IP}" \
  "${REMOTE_EXPORTS}; bash <(curl -fsSL ${DOTFILES_URL}) ${DOTFILES_FLAGS}"

log_ok "VPS ${VPS_IP} setup complete!"
echo ""
echo "Next steps:"
echo "  Install k3s server:"
echo "    make k3s-server"
