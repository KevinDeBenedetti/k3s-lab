#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-seed-cloudflare.sh — Seed Cloudflare API token into Vault
#
# Used by cert-manager to solve DNS-01 challenges.
# Run AFTER Vault is initialized and unsealed: make vault-seed-cloudflare
#
# Required:
#   VAULT_ROOT_TOKEN        Vault root token
#   CLOUDFLARE_API_TOKEN    Cloudflare API token (prompted if not set)
# =============================================================================

# shellcheck source=lib/script-init.sh
_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_src}" && "${_src}" != /dev/fd/* && -f "${_src}" ]]; then
  source "$(cd "$(dirname "${_src}")" && pwd)/../lib/script-init.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}/lib/script-init.sh")
fi
unset _src

_lib require-vars.sh
_lib vault.sh

require_vars VAULT_ROOT_TOKEN

_cf_token="${CLOUDFLARE_API_TOKEN:-}"
if [[ -z "$_cf_token" ]]; then
  read -rp "  CLOUDFLARE_API_TOKEN: " _cf_token < /dev/tty
fi
[[ -n "$_cf_token" ]] || { log_error "CLOUDFLARE_API_TOKEN required"; exit 1; }

vault_kv_put secret/cert-manager/cloudflare api-token="$_cf_token"

log_ok "cert-manager/cloudflare secret stored in Vault"
