#!/bin/bash
set -euo pipefail

# =============================================================================
# generate-inventory.sh — Generate the Ansible inventory from Terraform outputs
#
# Optional path. A homelab on hand-picked machines does not need it: copy
# ansible/inventory.example.yml and edit it. This script is for clusters whose
# nodes are created by Terraform; it turns the Terraform outputs into
# inventory/hosts.yml and inventory/group_vars/all/generated.yml.
#
# Run it from the repository that operates the cluster: paths default to the
# current directory (K3S_LAB_PROJECT_DIR), never to this k3s-lab checkout.
#
# ── Terraform output contract ────────────────────────────────────────────────
# Your Terraform root module (TF_DIR) must expose:
#
#   server_name        string   inventory name of the k3s server       REQUIRED
#   server_ip          string   address Ansible reaches it on (SSH)    REQUIRED
#   server_private_ip  string   cluster address → k3s_node_ip          optional
#   agent_names        list     inventory names of the agents          optional
#   agent_ips          list     their SSH addresses, same order        optional
#   agent_private_ips  list     their cluster addresses, same order    optional
#
# The agent lists are optional together (no outputs = a single-node cluster),
# but agent_names and agent_ips must have the same length when present.
# ─────────────────────────────────────────────────────────────────────────────
#
# Environment (from .env, CLUSTER_ENV or the shell):
#   K3S_VERSION         exact k3s release, e.g. v1.32.13+k3s1       REQUIRED
#   CLUSTER_DOMAIN      written as cluster_domain                    REQUIRED
#   CLUSTER_ENV         an extra env file to load first             optional
#   TF_DIR              default: ${K3S_LAB_PROJECT_DIR}/terraform
#   ANSIBLE_DIR         default: ${K3S_LAB_PROJECT_DIR}/ansible
#   K3S_UFW_ALLOW_FROM  CIDR allowed to reach the k3s ports (default: 10.0.0.0/16)
#   TERRAFORM           terraform command (default: terraform; tofu works too)
#
# Generated variables go to group_vars/all/generated.yml, NOT group_vars/all.yml:
# that file is yours (the docs tell you to put overrides there), and Ansible
# loads both. A group_vars/all.yml left by an older version of this script is
# recognised by its header and removed; any other all.yml is left untouched.
# =============================================================================

# shellcheck source=lib/script-init.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/script-init.sh"

_lib require-vars.sh

CLUSTER_ENV="${CLUSTER_ENV:-}"
TF_DIR="${TF_DIR:-${K3S_LAB_PROJECT_DIR}/terraform}"
ANSIBLE_DIR="${ANSIBLE_DIR:-${K3S_LAB_PROJECT_DIR}/ansible}"
TERRAFORM="${TERRAFORM:-terraform}"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.yml"
GENERATED_VARS_FILE="${ANSIBLE_DIR}/inventory/group_vars/all/generated.yml"
# Written by older versions of this script; also where the docs put overrides.
LEGACY_VARS_FILE="${ANSIBLE_DIR}/inventory/group_vars/all.yml"
GENERATED_HEADER="# Auto-generated from"

for bin in "$TERRAFORM" jq; do
  command -v "$bin" >/dev/null 2>&1 || { log_error "${bin} not found in PATH"; exit 1; }
done

# ── Load cluster config ──────────────────────────────────────────────────────
if [[ -n "$CLUSTER_ENV" ]]; then
  if [[ ! -f "$CLUSTER_ENV" ]]; then
    log_error "Cluster config not found: ${CLUSTER_ENV}"
    exit 1
  fi
  set -a
  # shellcheck source=/dev/null
  source "$CLUSTER_ENV"
  set +a
fi

require_vars K3S_VERSION CLUSTER_DOMAIN

# ── Read the Terraform outputs ───────────────────────────────────────────────
# -chdir, not `cd`: ANSIBLE_DIR may be relative (the provision taskfile passes
# `ansible`), and a cd here would land the inventory under TF_DIR.
TF_OUTPUTS="$("$TERRAFORM" -chdir="$TF_DIR" output -json)" || {
  log_error "Could not read the Terraform outputs in ${TF_DIR} (terraform init/apply first?)"
  exit 1
}

# tf_value <name> <jq-default> — an output's value as JSON, or the default.
tf_value() {
  jq -c --arg n "$1" --argjson d "$2" 'if has($n) then .[$n].value else $d end' <<<"$TF_OUTPUTS"
}

missing=()
for name in server_name server_ip; do
  [[ "$(tf_value "$name" null)" != "null" ]] || missing+=("$name")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  log_error "Terraform output(s) missing in ${TF_DIR}: ${missing[*]} — see the contract in $(basename "$0")"
  exit 1
fi

SERVER_NAME="$(tf_value server_name null | jq -r .)"
SERVER_IP="$(tf_value server_ip null | jq -r .)"
SERVER_PRIVATE_IP="$(tf_value server_private_ip '""' | jq -r .)"
AGENT_NAMES="$(tf_value agent_names '[]')"
AGENT_IPS="$(tf_value agent_ips '[]')"
AGENT_PRIVATE_IPS="$(tf_value agent_private_ips '[]')"
AGENT_COUNT="$(jq 'length' <<<"$AGENT_NAMES")"

if [[ "$(jq 'length' <<<"$AGENT_IPS")" -ne "$AGENT_COUNT" ]]; then
  log_error "agent_names and agent_ips have different lengths"
  exit 1
fi

# ── Generate group_vars/all/generated.yml ────────────────────────────────────
if [[ -f "$LEGACY_VARS_FILE" ]] && head -2 "$LEGACY_VARS_FILE" | grep -q "^${GENERATED_HEADER}"; then
  rm -f "$LEGACY_VARS_FILE"
  log_warn "Removed ${LEGACY_VARS_FILE}, generated by an older version — now ${GENERATED_VARS_FILE}"
fi

mkdir -p "$(dirname "$GENERATED_VARS_FILE")"
cat > "$GENERATED_VARS_FILE" << EOF
---
${GENERATED_HEADER} ${CLUSTER_ENV:-the environment} — do not edit manually
# Regenerate with: task provision:inventory. Overrides go in group_vars/all.yml.
k3s_version: "${K3S_VERSION}"
k3s_ufw_allow_from: "${K3S_UFW_ALLOW_FROM:-10.0.0.0/16}"
cluster_domain: "${CLUSTER_DOMAIN}"
EOF
log_ok "group_vars written to: ${GENERATED_VARS_FILE}"

# ── Generate hosts.yml ───────────────────────────────────────────────────────
mkdir -p "$(dirname "$INVENTORY_FILE")"

{
  cat << EOF
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
  [[ -z "$SERVER_PRIVATE_IP" ]] || echo "          k3s_node_ip: \"${SERVER_PRIVATE_IP}\""

  echo "    k3s_agents:"
  if [[ "$AGENT_COUNT" -eq 0 ]]; then
    echo "      hosts: {}  # no agent nodes"
  else
    echo "      hosts:"
    for ((i = 0; i < AGENT_COUNT; i++)); do
      name="$(jq -r ".[$i]" <<<"$AGENT_NAMES")"
      ip="$(jq -r ".[$i]" <<<"$AGENT_IPS")"
      priv="$(jq -r "if length > $i then .[$i] else \"\" end" <<<"$AGENT_PRIVATE_IPS")"
      echo "        ${name}:"
      echo "          ansible_host: \"${ip}\""
      [[ -z "$priv" ]] || echo "          k3s_node_ip: \"${priv}\""
    done
  fi
} > "$INVENTORY_FILE"

log_ok "Inventory written to: ${INVENTORY_FILE} (1 server, ${AGENT_COUNT} agent(s))"
