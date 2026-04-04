#!/bin/bash
set -euo pipefail

# =============================================================================
# k3s Agent Node Installation
# =============================================================================
# Usage: bash install-agent.sh
# Required env vars:
#   SERVER_IP       – public IP of the server VPS
#   K3S_NODE_TOKEN  – token from server (/var/lib/rancher/k3s/server/node-token)
# Optional:
#   K3S_VERSION     – must match server version, e.g. v1.32.2+k3s1
# =============================================================================

# --- Shared kernel/sysctl/swap setup (identical on server and agent) ---------
setup_kernel() {
  echo "→ Disabling swap..."
  swapoff -a
  sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

  echo "→ Loading kernel modules..."
  modprobe overlay
  modprobe br_netfilter

  cat > /etc/modules-load.d/k3s.conf << 'MOD'
overlay
br_netfilter
MOD

  # NOTE: prefix '99-z-' ensures this file sorts AFTER dotfiles' 99-security.conf,
  # so ip_forward=1 is the final applied value and k3s networking works correctly.
  cat > /etc/sysctl.d/99-z-k3s.conf << 'SYSCTL'
# k3s networking requirements — must override any earlier 99-security.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
# Required by --protect-kernel-defaults
vm.panic_on_oom                     = 0
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
SYSCTL

  sysctl --system
}

echo "🚀 Installing k3s — Agent Node"

# --- Variables ---
SERVER_IP="${SERVER_IP:?'Error: export SERVER_IP=<server-public-ip>'}"
K3S_NODE_TOKEN="${K3S_NODE_TOKEN:?'Error: export K3S_NODE_TOKEN=<token-from-server>'}"
K3S_VERSION="${K3S_VERSION:-v1.32.2+k3s1}"
NODE_IP=$(hostname -I | awk '{print $1}')

echo "🔍 Server:  ${SERVER_IP}"
echo "🔍 Node IP: ${NODE_IP}"

setup_kernel

# --- Install k3s agent ---
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_TOKEN="${K3S_NODE_TOKEN}" \
  sh -s - agent \
    --server="https://${SERVER_IP}:6443" \
    --node-ip="${NODE_IP}" \
    --protect-kernel-defaults \
    --node-label="node-role=worker"

echo ""
echo "✅ Agent node joined the cluster!"
echo ""
echo "Verify on the server with:"
echo "  kubectl get nodes -o wide"

# --- Configure UFW for k3s (if active — installed by dotfiles setup-security.sh) ---
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "🔥 Configuring UFW for k3s..."
  # Allow traffic from server (VXLAN tunnel + kubelet checks)
  ufw allow from "${SERVER_IP}" to any port 8472 proto udp comment 'flannel VXLAN from server'
  ufw allow from "${SERVER_IP}" to any port 10250 proto tcp comment 'k3s kubelet from server'
  ufw allow from 10.42.0.0/16 to any comment 'k3s pod traffic'
  ufw allow from 10.43.0.0/16 to any comment 'k3s service traffic'
  ufw reload
fi
