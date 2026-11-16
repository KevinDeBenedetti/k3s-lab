#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-init.sh — Initialise (or unseal) Vault, then configure it
#
# Run AFTER the Vault pod is Running: task vault:init
#
#   1. Wait for the Vault pod to be Ready
#   2. Initialise it if needed — prints the unseal keys and the root token,
#      which are never shown again — or unseal it if it is sealed
#   3. Configure it (same steps as vault-configure.sh): KV v2 at secret/,
#      Kubernetes auth, policies from VAULT_POLICY_DIR, the External Secrets
#      role, and OIDC when all of its five variables are set
#
# Safe to re-run: on an initialised Vault it only unseals and reconfigures.
# Configuration: see lib/vault.sh.
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib vault.sh

vault_require_tools
vault_wait_ready
vault_check_reachable

if vault_is_initialized; then
  log_info "Vault is already initialized — skipping init"
  vault_unseal
else
  vault_initialize
  vault_unseal
fi

vault_use_root_token
vault_configure

echo ""
echo "Next steps:"
echo "  task vault:seed                     # store secrets into Vault"
echo "  (ArgoCD deploys External Secrets Operator and applies the ClusterSecretStore + ExternalSecrets from Git)"
