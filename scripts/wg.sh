#!/bin/bash
set -euo pipefail

# =============================================================================
# wg.sh — WireGuard VPN helper for the local client
#
# Thin wrapper over wg-quick to bring the tunnel up/down so you can reach the
# cluster (ArgoCD UI, Vault, Kubernetes API, …) over the VPN. The config is
# read by wg-quick itself (default: /etc/wireguard/<interface>.conf).
#
# Usage:
#   ./scripts/wg.sh up        # connect
#   ./scripts/wg.sh down      # disconnect
#   ./scripts/wg.sh status    # show tunnel status
#
# Optional:
#   WG_INTERFACE   WireGuard interface name (default: wg0)
# =============================================================================

WG_INTERFACE="${WG_INTERFACE:-wg0}"

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/v0.11.1}" # x-release-please-version

# wg.sh takes a positional subcommand and never needs .env — keep the manual
# preamble (run-mode.sh + log.sh) instead of script-init.sh, which would load .env.
_run_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  source "$(cd "$(dirname "${_run_src}")" && pwd)/../lib/run-mode.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW}/lib/run-mode.sh")
fi

_lib log.sh

# Connection state from wg-quick's own runtime marker (created on up, removed on
# down) — reliable and independent of the client IP or interface naming.
wg_connected() { [[ -e "/var/run/wireguard/${WG_INTERFACE}.name" ]]; }

wg_up() {
  command -v wg-quick >/dev/null 2>&1 \
    || { log_error "wg-quick not found — install wireguard-tools (e.g. brew install wireguard-tools)"; exit 1; }
  if wg_connected; then
    log_info "Already connected (${WG_INTERFACE})"
  else
    sudo wg-quick up "${WG_INTERFACE}" && log_ok "WireGuard connected (${WG_INTERFACE})"
  fi
}

wg_down() {
  if wg_connected; then
    sudo wg-quick down "${WG_INTERFACE}" && log_ok "WireGuard disconnected (${WG_INTERFACE})"
  else
    log_info "Already disconnected (${WG_INTERFACE})"
  fi
}

wg_status() {
  if wg_connected; then
    log_ok "WireGuard connected (${WG_INTERFACE})"
    command -v wg >/dev/null 2>&1 && sudo wg show "${WG_INTERFACE}"
  else
    log_info "WireGuard disconnected (${WG_INTERFACE})"
  fi
}

case "${1:-}" in
  up)     wg_up ;;
  down)   wg_down ;;
  status) wg_status ;;
  *) echo "Usage: $0 {up|down|status}" >&2; exit 2 ;;
esac
