#!/bin/bash
set -euo pipefail

# =============================================================================
# get-kubeconfig.sh — Fetch kubeconfig from master and merge into ~/.kube/config
# Usage: ./scripts/get-kubeconfig.sh <MASTER_IP> [SSH_USER] [CONTEXT_NAME]
#
# Examples:
#   ./scripts/get-kubeconfig.sh 1.2.3.4
#   ./scripts/get-kubeconfig.sh 1.2.3.4 kevin my-cluster
# =============================================================================

MASTER_IP="${1:?'Usage: ./scripts/get-kubeconfig.sh <MASTER_IP> [SSH_USER] [CONTEXT_NAME]'}"
SSH_USER="${2:-${SSH_USER:-kevin}}"
CONTEXT_NAME="${3:-${KUBECONFIG_CONTEXT:-k3s-infra}}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"

_run_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  source "$(cd "$(dirname "${_run_src}")" && pwd)/../lib/run-mode.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW}/lib/run-mode.sh")
fi

_lib log.sh
_lib ssh-opts.sh

TMP_KUBECONFIG="$(mktemp)"
TARGET="${HOME}/.kube/config"
mkdir -p "${HOME}/.kube"
chmod 700 "${HOME}/.kube"

build_ssh_opts "${SSH_PORT}" "no"

log_info "Fetching kubeconfig from ${SSH_USER}@${MASTER_IP} (port ${SSH_PORT})..."

# Fetch, rewrite the localhost address and cluster/context/user names
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${MASTER_IP}" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127\.0\.0\.1/${MASTER_IP}/g" \
  | sed "s/name: default/name: ${CONTEXT_NAME}/g" \
  | sed "s/cluster: default/cluster: ${CONTEXT_NAME}/g" \
  | sed "s/user: default/user: ${CONTEXT_NAME}/g" \
  | sed "s/current-context: default/current-context: ${CONTEXT_NAME}/g" \
  > "${TMP_KUBECONFIG}"

chmod 600 "${TMP_KUBECONFIG}"

# Merge into existing kubeconfig (or create it if it doesn't exist)
if [[ -f "${TARGET}" ]]; then
  log_info "Merging into existing ${TARGET}..."
  KUBECONFIG="${TARGET}:${TMP_KUBECONFIG}" kubectl config view --flatten > "${TARGET}.merged"
  mv "${TARGET}.merged" "${TARGET}"
else
  log_info "Creating new kubeconfig at ${TARGET}..."
  cp "${TMP_KUBECONFIG}" "${TARGET}"
fi

chmod 600 "${TARGET}"
rm -f "${TMP_KUBECONFIG}"

log_ok "Context '${CONTEXT_NAME}' added to ${TARGET}"
echo ""
echo "Switch to this cluster:"
echo "  kubectl config use-context ${CONTEXT_NAME}"
echo ""
echo "Verify cluster access:"
echo "  kubectl get nodes -o wide"
