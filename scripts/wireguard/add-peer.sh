#!/usr/bin/env bash
# =============================================================================
# add-peer.sh — Add a WireGuard peer to an existing wg0 server
#
# Called via: make wg-peer-add
# Environment (injected by Makefile via SSH env):
#   WG_CLIENT_PUBKEY — peer's WireGuard public key (base64)
#   WG_CLIENT_IP     — peer's tunnel IP (e.g. 10.8.0.2)
#   WG_PEER_NAME     — human-readable label for the peer (e.g. laptop)
# =============================================================================
set -euo pipefail

WG_CLIENT_PUBKEY="${WG_CLIENT_PUBKEY:?WG_CLIENT_PUBKEY is required}"
WG_CLIENT_IP="${WG_CLIENT_IP:-10.8.0.2}"
WG_PEER_NAME="${WG_PEER_NAME:-peer}"

CONF=/etc/wireguard/wg0.conf

# Idempotent: skip if this public key is already present
if sudo grep -q "${WG_CLIENT_PUBKEY}" "${CONF}" 2>/dev/null; then
  echo "⚠️  Peer ${WG_PEER_NAME} (${WG_CLIENT_IP}) already exists — skipping"
  exit 0
fi

echo "→ Adding peer '${WG_PEER_NAME}' (${WG_CLIENT_IP})..."
sudo tee -a "${CONF}" > /dev/null << PEER

# Peer: ${WG_PEER_NAME}
[Peer]
PublicKey  = ${WG_CLIENT_PUBKEY}
AllowedIPs = ${WG_CLIENT_IP}/32
PEER

# Hot-reload: add peer to running interface without restarting
sudo wg set wg0 peer "${WG_CLIENT_PUBKEY}" allowed-ips "${WG_CLIENT_IP}/32"

echo "✅ Peer '${WG_PEER_NAME}' added at ${WG_CLIENT_IP}"
echo "   Run 'sudo wg show' to verify"
