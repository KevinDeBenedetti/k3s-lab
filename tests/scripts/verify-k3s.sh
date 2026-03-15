#!/bin/bash
# verify-k3s.sh — Run inside the Lima k3s VM after make vm-k3s-install
# Checks that k3s is properly installed, the node is Ready, and system pods run.
# Usage: limactl shell infra-k3s-vm sudo bash tests/scripts/verify-k3s.sh
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

PASS=0
FAIL=0

ok()   { echo "  ✅ $*"; PASS=$(( PASS + 1 )); }
fail() { echo "  ❌ $*"; FAIL=$(( FAIL + 1 )); }
section() { echo ""; echo "=== $* ==="; }

# ─────────────────────────────────────────────
# k3s service
# ─────────────────────────────────────────────
section "🚀 k3s Service"
systemctl is-active k3s &>/dev/null \
  && ok "k3s.service active" \
  || fail "k3s.service not active"

systemctl is-enabled k3s &>/dev/null \
  && ok "k3s.service enabled (survives reboot)" \
  || fail "k3s.service not enabled"

# ─────────────────────────────────────────────
# Node status
# ─────────────────────────────────────────────
section "☸️  Node"
if ! command -v kubectl &>/dev/null; then
  fail "kubectl not found"
else
  ok "kubectl: $(k3s --version 2>/dev/null | awk 'NR==1 {print $3}')"
  NODE_STATUS=$(k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
  [ "$NODE_STATUS" = "Ready" ] \
    && ok "Node status: Ready" \
    || fail "Node status: ${NODE_STATUS:-unknown} (expected Ready)"
fi

# ─────────────────────────────────────────────
# System pods
# ─────────────────────────────────────────────
section "🐳 System Pods (kube-system)"
# Wait up to 60s for all kube-system pods to be scheduled
k3s kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=60s &>/dev/null || true
declare -a EXPECTED_PODS=("coredns" "local-path-provisioner" "metrics-server" "traefik")
for pod in "${EXPECTED_PODS[@]}"; do
  # '|| true' prevents set -e from aborting when grep finds no match (exit 1)
  STATUS=$(k3s kubectl get pods -n kube-system --no-headers 2>/dev/null \
    | grep "$pod" | awk '{print $3}' | head -1) || true
  if [ "$STATUS" = "Running" ]; then
    ok "${pod}: Running"
  elif [ -z "$STATUS" ]; then
    # traefik is disabled in install-master.sh — skip if not found
    [[ "$pod" == "traefik" ]] \
      && echo "  ⏭  ${pod}: disabled (expected — install-master.sh uses --disable=traefik)" \
      || fail "${pod}: not found"
  else
    fail "${pod}: ${STATUS} (expected Running)"
  fi
done

# ─────────────────────────────────────────────
# Security configuration
# ─────────────────────────────────────────────
section "🔒 Security"
test -f /var/lib/rancher/k3s/server/tls/server-ca.crt \
  && ok "TLS: server CA cert exists" \
  || fail "TLS: server CA cert missing"

test -f /etc/rancher/k3s/k3s.yaml \
  && ok "kubeconfig: /etc/rancher/k3s/k3s.yaml exists" \
  || fail "kubeconfig: /etc/rancher/k3s/k3s.yaml missing"

KUBECONFIG_PERMS=$(stat -c "%a" /etc/rancher/k3s/k3s.yaml 2>/dev/null || echo "000")
[ "$KUBECONFIG_PERMS" = "600" ] \
  && ok "kubeconfig permissions: 600" \
  || fail "kubeconfig permissions: ${KUBECONFIG_PERMS} (expected 600)"

# ─────────────────────────────────────────────
# Kernel parameters (--protect-kernel-defaults)
# ─────────────────────────────────────────────
section "⚙️  Sysctl (k3s requirements)"
declare -A EXPECTED=(
  ["vm.panic_on_oom"]="0"
  ["vm.overcommit_memory"]="1"
  ["kernel.panic"]="10"
  ["net.ipv4.ip_forward"]="1"
  ["net.bridge.bridge-nf-call-iptables"]="1"
)
for key in "${!EXPECTED[@]}"; do
  val="$(sysctl -n "$key" 2>/dev/null || echo '')"
  [ "$val" = "${EXPECTED[$key]}" ] \
    && ok "${key} = ${val}" \
    || fail "${key} = ${val:-<unset>} (expected ${EXPECTED[$key]})"
done

# ─────────────────────────────────────────────
# Resource usage
# ─────────────────────────────────────────────
section "💾 Resource Usage"
echo "  RAM:    $(free -h | awk '/^Mem:/{printf "%s used / %s total", $3, $2}')"
echo "  Disk:   $(df -h / | tail -1 | awk '{printf "%s used / %s total (%s free)", $3, $2, $4}')"
echo "  Swap:   $(free -h | awk '/^Swap:/{print $3 " used / " $2 " total"}')"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "─────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ All ${PASS} checks passed — k3s cluster is healthy"
else
  echo "❌ ${FAIL} check(s) failed, ${PASS} passed"
  exit 1
fi
