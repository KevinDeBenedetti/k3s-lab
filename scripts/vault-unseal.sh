#!/bin/bash
set -euo pipefail

# =============================================================================
# vault-unseal.sh — Unseal Vault after a pod restart (e.g. a node reboot)
#
# Feeds VAULT_UNSEAL_KEY_1, VAULT_UNSEAL_KEY_2, … one at a time and stops as
# soon as Vault reports unsealed, so only the threshold number of keys is used.
# A key that is not set is asked for on the terminal. Does nothing on an
# unsealed Vault.
#
# Called by: task vault:unseal. Configuration: see lib/vault.sh.
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib vault.sh

vault_require_tools
vault_unseal
