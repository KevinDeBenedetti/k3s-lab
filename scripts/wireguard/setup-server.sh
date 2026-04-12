#!/usr/bin/env bash
# =============================================================================
# setup-server.sh — Install and configure WireGuard server on a VPS
#
# Called via: make wg-server-up
# Environment (injected by Makefile via SSH env):
#   WG_SERVER_IP  — server tunnel IP (e.g. 10.8.0.1)
#   WG_PORT       — UDP listen port  (e.g. 51820)
#   WG_SUBNET     — full CIDR subnet (e.g. 10.8.0.0/24)
# =============================================================================
set -euo pipefail

WG_SERVER_IP="${WG_SERVER_IP:-10.8.0.1}"
WG_PORT="${WG_PORT:-51820}"
WG_SUBNET="${WG_SUBNET:-10.8.0.0/24}"

# Detect the public-facing network interface (usually eth0 or ens3)
WAN_IF=$(ip route get ${WG_ROUTE_IP:-1.1.1.1} | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')

echo "→ Installing WireGuard..."
sudo apt-get update -qq
sudo apt-get install -y wireguard wireguard-tools

echo "→ Generating server keys..."
sudo mkdir -p /etc/wireguard
wg genkey | sudo tee /etc/wireguard/server.key | wg pubkey | sudo tee /etc/wireguard/server.pub
sudo chmod 600 /etc/wireguard/server.key

echo "→ Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-wireguard.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null

echo "→ Writing /etc/wireguard/wg0.conf..."
SERVER_KEY=$(sudo cat /etc/wireguard/server.key)
sudo tee /etc/wireguard/wg0.conf > /dev/null << WGCONF
[Interface]
Address    = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_KEY}

# NAT: masquerade WireGuard traffic through the VPS public interface
PostUp   = iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${WAN_IF} -j MASQUERADE; \
           ufw allow ${WG_PORT}/udp comment 'WireGuard'
PostDown = iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o ${WAN_IF} -j MASQUERADE; \
           ufw delete allow ${WG_PORT}/udp
WGCONF
sudo chmod 600 /etc/wireguard/wg0.conf

echo "→ Starting wg-quick@wg0..."
sudo systemctl enable --now wg-quick@wg0

echo ""
echo "✅ WireGuard server running on ${WG_SERVER_IP}:${WG_PORT}"
echo "   Server public key: $(sudo cat /etc/wireguard/server.pub)"
echo ""
echo "Next: add a peer with:"
echo "  make wg-peer-add WG_CLIENT_PUBKEY=<client-pubkey> WG_CLIENT_IP=10.8.0.2"
echo "  Or:  make wg-client-config   (auto-generates client keys + adds peer)"
