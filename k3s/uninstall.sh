#!/bin/bash
set -euo pipefail

# =============================================================================
# k3s Uninstall — Remove k3s from a node
# Run on the node you want to reset (master or worker).
# =============================================================================

echo "⚠️  This will completely remove k3s from this node."
read -r -p "Continue? [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# Worker agent uninstall script (present when node joined as agent)
if [[ -f /usr/local/bin/k3s-agent-uninstall.sh ]]; then
  echo "→ Removing k3s agent..."
  /usr/local/bin/k3s-agent-uninstall.sh
# Server uninstall script (present when installed as server)
elif [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
  echo "→ Removing k3s server..."
  /usr/local/bin/k3s-uninstall.sh
else
  echo "✅ No k3s installation found on this node."
  exit 0
fi

# Clean up leftover network interfaces (vxlan, flannel)
for iface in flannel.1 cni0 kube-ipvs0; do
  if ip link show "${iface}" &>/dev/null; then
    echo "→ Removing network interface ${iface}..."
    ip link delete "${iface}" 2>/dev/null || true
  fi
done

# Remove iptables rules left by k3s
if command -v iptables &>/dev/null; then
  echo "→ Flushing iptables rules..."
  iptables -F
  iptables -t nat -F
  iptables -t mangle -F
  iptables -X 2>/dev/null || true
fi

echo ""
echo "✅ k3s removed from this node."
