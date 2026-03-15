#!/bin/bash
# verify-vps.sh — Run inside the Lima VPS VM after make vm-vps-install
# Checks that the dotfiles kubernetes profile was applied correctly.
# Usage: limactl shell infra-vps-vm bash tests/scripts/verify-vps.sh
set -euo pipefail

PASS=0
FAIL=0

ok()   { echo "  ✅ $*"; PASS=$(( PASS + 1 )); }
fail() { echo "  ❌ $*"; FAIL=$(( FAIL + 1 )); }
section() { echo ""; echo "=== $* ==="; }

# ─────────────────────────────────────────────
# Kernel modules (loaded by setup-kubernetes.sh)
# ─────────────────────────────────────────────
section "🧩 Kernel Modules"
for mod in overlay br_netfilter; do
  lsmod | grep -q "^${mod}" \
    && ok "${mod} loaded" \
    || fail "${mod} NOT loaded"
done
test -f /etc/modules-load.d/k8s.conf \
  && ok "k8s.conf persist file exists" \
  || fail "/etc/modules-load.d/k8s.conf missing"

# ─────────────────────────────────────────────
# Sysctl (applied by setup-kubernetes.sh)
# ─────────────────────────────────────────────
section "⚙️  Sysctl"
declare -A EXPECTED=(
  ["net.ipv4.ip_forward"]="1"
  ["net.bridge.bridge-nf-call-iptables"]="1"
  ["net.bridge.bridge-nf-call-ip6tables"]="1"
)
for key in "${!EXPECTED[@]}"; do
  val="$(sysctl -n "$key" 2>/dev/null || echo '')"
  [ "$val" = "${EXPECTED[$key]}" ] \
    && ok "${key} = ${val}" \
    || fail "${key} = ${val:-<unset>} (expected ${EXPECTED[$key]})"
done

# ─────────────────────────────────────────────
# Tools installed by kubernetes profile
# ─────────────────────────────────────────────
section "📦 Binaries"
# kubectl: required on the VPS for local cluster access
# helm/k9s: run from your Mac — not needed on the server itself
for cmd in kubectl curl git; do
  command -v "$cmd" &>/dev/null \
    && ok "${cmd}: $(command -v "$cmd")" \
    || fail "${cmd} not found"
done
# helm is optional on the server (mainly a Mac-side tool)
command -v helm &>/dev/null \
  && ok "helm: $(command -v helm) (optional)" \
  || echo "  ℹ️  helm not installed (managed from Mac — OK)"

# ─────────────────────────────────────────────
# OS info
# ─────────────────────────────────────────────
section "🖥️  System"
echo "  OS:     $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "  Kernel: $(uname -r)"
echo "  RAM:    $(free -h | awk '/^Mem:/{print $2}')"
echo "  Disk:   $(df -h / | tail -1 | awk '{print $4}') free"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "─────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ All ${PASS} checks passed"
else
  echo "❌ ${FAIL} check(s) failed, ${PASS} passed"
  exit 1
fi
