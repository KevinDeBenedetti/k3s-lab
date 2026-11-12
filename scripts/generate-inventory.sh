#!/bin/bash
set -euo pipefail

# =============================================================================
# generate-inventory.sh — Generate Ansible inventory from Terraform outputs
#
# Reads cluster configuration from CLUSTER_ENV and Terraform outputs to
# produce hosts.yml and group_vars/all.yml for Ansible provisioning.
#
# Run it from the repository that operates the cluster: paths default to the
# current directory (K3S_LAB_PROJECT_DIR), never to this k3s-lab checkout.
#
# Required:
#   CLUSTER_ENV     Path to the env file holding K3S_VERSION and CLUSTER_DOMAIN
#
# Optional:
#   TF_DIR              Terraform directory (default: ${K3S_LAB_PROJECT_DIR}/terraform)
#   ANSIBLE_DIR         Ansible directory (default: ${K3S_LAB_PROJECT_DIR}/ansible)
#   K3S_UFW_ALLOW_FROM  CIDR allowed to reach the k3s ports (default: 10.0.0.0/16)
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib require-vars.sh

CLUSTER_ENV="${CLUSTER_ENV:-}"
TF_DIR="${TF_DIR:-${K3S_LAB_PROJECT_DIR}/terraform}"
ANSIBLE_DIR="${ANSIBLE_DIR:-${K3S_LAB_PROJECT_DIR}/ansible}"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.yml"
GROUP_VARS_FILE="${ANSIBLE_DIR}/inventory/group_vars/all.yml"

require_vars CLUSTER_ENV

if [[ ! -f "$CLUSTER_ENV" ]]; then
  log_error "Cluster config not found: ${CLUSTER_ENV}"
  exit 1
fi

# ── Load cluster config ──────────────────────────────────────────────────────
set -a
# shellcheck source=/dev/null
source "$CLUSTER_ENV"
set +a

require_vars K3S_VERSION CLUSTER_DOMAIN

# ── Generate group_vars/all.yml ──────────────────────────────────────────────
mkdir -p "$(dirname "$GROUP_VARS_FILE")"

cat > "$GROUP_VARS_FILE" << EOF
---
# Auto-generated from ${CLUSTER_ENV} — do not edit manually
# Regenerate with: task provision:inventory
k3s_version: "${K3S_VERSION}"
k3s_ufw_allow_from: "${K3S_UFW_ALLOW_FROM:-10.0.0.0/16}"

# Domain (from CLUSTER_DOMAIN in cluster.env)
cluster_domain: ${CLUSTER_DOMAIN}
EOF

log_ok "group_vars written to: ${GROUP_VARS_FILE}"

# ── Generate Ansible inventory from Terraform outputs ────────────────────────
# -chdir, not `cd`: ANSIBLE_DIR may be relative (the provision taskfile passes
# `ansible`), and a cd here would land the inventory under TF_DIR.
tf_output() { terraform -chdir="$TF_DIR" output "$@"; }

SERVER_IP=$(tf_output -raw server_ip)
SERVER_PRIVATE_IP=$(tf_output -raw server_private_ip 2>/dev/null || echo "")
SERVER_NAME=$(tf_output -raw server_name)

AGENT_IPS=$(tf_output -json agent_ips)
AGENT_PRIVATE_IPS=$(tf_output -json agent_private_ips)
AGENT_NAMES=$(tf_output -json agent_names)
AGENT_COUNT=$(echo "$AGENT_IPS" | jq 'length')

mkdir -p "$(dirname "$INVENTORY_FILE")"

cat > "$INVENTORY_FILE" << EOF
---
# Auto-generated from Terraform outputs — do not edit manually
# Regenerate with: task provision:inventory
all:
  children:
    k3s_servers:
      hosts:
        ${SERVER_NAME}:
          ansible_host: "${SERVER_IP}"
EOF

if [ -n "$SERVER_PRIVATE_IP" ]; then
  echo "          k3s_node_ip: \"${SERVER_PRIVATE_IP}\"" >> "$INVENTORY_FILE"
fi

cat >> "$INVENTORY_FILE" << EOF
    k3s_agents:
      hosts:
EOF

if [ "$AGENT_COUNT" -gt 0 ]; then
  for ((i=0; i<AGENT_COUNT; i++)); do
    NAME=$(echo "$AGENT_NAMES" | jq -r ".[$i]")
    IP=$(echo "$AGENT_IPS" | jq -r ".[$i]")
    PRIV_IP=$(echo "$AGENT_PRIVATE_IPS" | jq -r "if length > $i then .[$i] else \"\" end")
    cat >> "$INVENTORY_FILE" << EOF
        ${NAME}:
          ansible_host: "${IP}"
EOF
    if [ -n "$PRIV_IP" ]; then
      echo "          k3s_node_ip: \"${PRIV_IP}\"" >> "$INVENTORY_FILE"
    fi
  done
else
  echo "        {} # No agent nodes provisioned" >> "$INVENTORY_FILE"
fi

log_ok "Inventory written to: ${INVENTORY_FILE}"
