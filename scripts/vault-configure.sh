#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-configure.sh — (Re)apply Vault's engines, auth methods, policies and
# roles
#
# Idempotent — safe to run as often as needed. Run on an initialised, unsealed
# Vault: task vault:configure (vault-init.sh runs the same steps after init).
#
#   1. KV v2 secrets engine at secret/
#   2. Kubernetes auth method and its config
#   3. Every *.hcl in VAULT_POLICY_DIR, as a policy named after the file
#   4. The External Secrets role `eso` (policy eso-read)
#   5. OIDC auth and the `default` role (policy vault-admin) — only when
#      OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_ISSUER_URL, VAULT_DOMAIN and
#      ADMIN_EMAIL are all set; a partial set is refused before anything runs
#
# Needs VAULT_ROOT_TOKEN (from .env, or asked for on the terminal).
# Configuration: see lib/vault.sh.
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib vault.sh

vault_require_tools
vault_check_reachable

if vault_is_sealed; then
  log_error "Vault is sealed — run: task vault:unseal"
  exit 1
fi

vault_use_root_token
vault_configure
