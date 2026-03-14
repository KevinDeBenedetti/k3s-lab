#!/bin/bash
set -euo pipefail

# =============================================================================
# k3s Control Plane (Master) Installation
# =============================================================================
# Usage: bash install-master.sh
# Required env vars (can also be exported before running):
#   K3S_NODE_TOKEN   – shared secret used by workers to join (min 32 chars)
#   PUBLIC_IP        – public IP of this VPS (if different from primary NIC IP)
# Optional:
#   K3S_VERSION      – pin a specific version, e.g. v1.32.2+k3s1
# =============================================================================

echo "🚀 Installing k3s — Control Plane (Master)"

# --- Variables ---
K3S_VERSION="${K3S_VERSION:-v1.32.2+k3s1}"
NODE_IP=$(hostname -I | awk '{print $1}')
# If PUBLIC_IP is not set, fall back to the primary NIC IP
PUBLIC_IP="${PUBLIC_IP:-${NODE_IP}}"
# Optional: if WORKER_IP is already known, the VXLAN UFW rule is added here.
# Otherwise add it manually after the worker is provisioned:
#   ufw allow from <WORKER_IP> to any port 8472 proto udp comment 'flannel VXLAN from worker'
WORKER_IP="${WORKER_IP:-}"

# K3S_NODE_TOKEN: explicit shared secret so workers can join without reading
# the server-generated token from disk.
if [[ -z "${K3S_NODE_TOKEN:-}" ]]; then
  echo "⚠️  K3S_NODE_TOKEN is not set. Generating a random token."
  K3S_NODE_TOKEN=$(openssl rand -hex 32)
  echo "⚠️  Generated token: ${K3S_NODE_TOKEN}"
  echo "⚠️  Save this token — workers need it to join the cluster."
fi

# --- Disable swap (required for Kubernetes) ---
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# --- Kernel modules ---
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

# --- Install k3s server ---
# Key flags:
#   --disable traefik          → managed via Helm for full control
#   --disable servicelb        → managed via Helm (MetalLB or cloud LB)
#   --tls-san                  → add public IP to TLS SAN so kubeconfig works remotely
#   --flannel-backend=vxlan    → explicit VXLAN overlay (default, stable across versions)
#   --protect-kernel-defaults  → enforce kernel parameter requirements
#   --secrets-encryption       → encrypt Kubernetes secrets at rest
#   --write-kubeconfig-mode=600 → restrict kubeconfig permissions
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_TOKEN="${K3S_NODE_TOKEN}" \
  sh -s - server \
    --disable=traefik \
    --disable=servicelb \
    --node-ip="${NODE_IP}" \
    --advertise-address="${NODE_IP}" \
    --tls-san="${PUBLIC_IP}" \
    --flannel-backend=vxlan \
    --protect-kernel-defaults \
    --secrets-encryption \
    --write-kubeconfig-mode=600 \
    --node-label="node-role=master"

# --- Wait for node to be ready (timeout: 120s) ---
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "⏳ Waiting for control plane node to be Ready..."
TIMEOUT=120
ELAPSED=0
until kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready"; do
  if (( ELAPSED >= TIMEOUT )); then
    echo "❌ Timed out waiting for node to be ready."
    kubectl get nodes
    exit 1
  fi
  sleep 5
  ELAPSED=$(( ELAPSED + 5 ))
done

echo ""
echo "✅ Master node is Ready!"
echo ""
kubectl get nodes -o wide
echo ""

# --- Configure UFW for k3s (if active — installed by dotfiles setup-security.sh) ---
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "🔥 Configuring UFW for k3s..."
  ufw allow 80/tcp  comment 'HTTP (Traefik + ACME HTTP-01)'
  ufw allow 443/tcp comment 'HTTPS (Traefik TLS)'
  ufw allow 6443/tcp comment 'k3s API server'
  ufw allow from 10.42.0.0/16 to any comment 'k3s pod traffic'
  ufw allow from 10.43.0.0/16 to any comment 'k3s service traffic'
  # Allow VXLAN + kubelet from worker if known
  if [[ -n "${WORKER_IP}" ]]; then
    ufw allow from "${WORKER_IP}" to any port 8472 proto udp comment 'flannel VXLAN from worker'
    ufw allow from "${WORKER_IP}" to any port 10250 proto tcp comment 'k3s kubelet from worker'
  else
    echo "ℹ️  WORKER_IP not set — after provisioning the worker, run:"
    echo "   ufw allow from <WORKER_IP> to any port 8472 proto udp comment 'flannel VXLAN from worker'"
    echo "   ufw allow from <WORKER_IP> to any port 10250 proto tcp comment 'k3s kubelet from worker'"
  fi
  ufw reload
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Node join token (export before running install-worker.sh):"
echo "   export K3S_NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)"
echo ""
echo "📋 Kubeconfig path: /etc/rancher/k3s/k3s.yaml"
echo "   On your local machine, run:"
echo "   ./scripts/get-kubeconfig.sh ${PUBLIC_IP}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
