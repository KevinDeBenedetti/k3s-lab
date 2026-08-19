#!/usr/bin/env bash
# =============================================================================
# check-play-order.sh — Assert that the firewall is still enabled LAST.
#
# The invariant, and why it is worth a check of its own:
#
# UFW rules are added by four roles (common, k3s_server, k3s_agent, wireguard)
# and the firewall is turned ON by a fifth, `ufw_enable`, which the playbooks
# apply as their final play. That split is deliberate. Enabling UFW from inside
# `common` — as this repo did until 2026-08-17 — means a playbook interrupted
# anywhere between `common` and the end leaves the node behind an ACTIVE
# default-deny firewall holding only the rules reached so far: no API port, no
# ingress, possibly no WireGuard. The node is then reachable only through the
# provider's rescue console.
#
# Nothing about that ordering is self-enforcing. Adding a role after
# `ufw_enable`, or moving the play up "so the firewall is on sooner", reads as an
# improvement and breaks it silently — the playbook still parses, still lints,
# still syntax-checks, and the damage only shows on the next interrupted run
# against a real node. `--syntax-check` and ansible-lint both pass on a playbook
# with the plays in the wrong order, so neither can catch this.
#
# What is asserted comes from `ansible-playbook --list-tasks`, i.e. the order
# ansible ITSELF resolves after expanding every role — not from reading the YAML
# and hoping the reader and ansible agree.
#
# Usage:
#   scripts/check-play-order.sh
#   scripts/check-play-order.sh --playbooks ansible/playbooks
#
# Env:
#   ANSIBLE_PLAYBOOK  ansible-playbook command to use (default
#                     `ansible-playbook`) — injection point for the tests, which
#                     must run where ansible is not installed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"

ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-ansible-playbook}"
PLAYBOOK_DIR="$REPO_ROOT/ansible/playbooks"

# Roles that add UFW rules. A playbook applying any of them must also enable the
# firewall, or it leaves rules staged behind a firewall nobody ever turns on.
GUARDED_ROLES="common k3s_server k3s_agent wireguard"
ENABLER_ROLE="ufw_enable"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --playbooks) PLAYBOOK_DIR="$2"; shift 2 ;;
    -h|--help)
      awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -d "$PLAYBOOK_DIR" ] || { log_error "No such playbook directory: $PLAYBOOK_DIR"; exit 2; }

shopt -s nullglob
playbooks=("$PLAYBOOK_DIR"/*.yml)
shopt -u nullglob

if [ "${#playbooks[@]}" -eq 0 ]; then
  log_error "No playbook found in $PLAYBOOK_DIR — refusing to report success."
  exit 2
fi

log_step "Checking play order in ${#playbooks[@]} playbook(s)"

errors=0

for playbook in "${playbooks[@]}"; do
  rel="${playbook#"$REPO_ROOT"/}"

  # Run from the directory holding ansible.cfg (the playbook dir's parent):
  # `roles_path = roles` is relative to it, and from anywhere else every role
  # fails to resolve and the listing comes back empty — which would make this
  # check pass vacuously rather than fail.
  if ! listing="$(cd "$PLAYBOOK_DIR/.." && "$ANSIBLE_PLAYBOOK" --list-tasks -i localhost, "$playbook" 2>/dev/null)"; then
    log_error "  $rel — \`--list-tasks\` failed, the order could not be checked"
    errors=$((errors + 1))
    continue
  fi

  # "role : Task name" lines only. Tasks written directly in a play carry no
  # role prefix and are irrelevant to an assertion about role ordering.
  mapfile -t roles_in_order < <(
    printf '%s\n' "$listing" \
      | sed -n 's/^[[:space:]]*\([a-z0-9_]*\)[[:space:]]*:[[:space:]].*TAGS:.*$/\1/p'
  )

  if [ "${#roles_in_order[@]}" -eq 0 ]; then
    log_info "  $rel — applies no role, nothing to order"
    continue
  fi

  needs_firewall=0
  for role in "${roles_in_order[@]}"; do
    case " $GUARDED_ROLES " in
      *" $role "*) needs_firewall=1; break ;;
    esac
  done

  if [ "$needs_firewall" -eq 0 ]; then
    log_info "  $rel — adds no UFW rule, nothing to order"
    continue
  fi

  last_role="${roles_in_order[-1]}"

  if [ "$last_role" != "$ENABLER_ROLE" ]; then
    log_error "  $rel — adds UFW rules but does NOT end with the '$ENABLER_ROLE' role"
    log_error "      last role to run is '$last_role'"
    if printf '%s\n' "${roles_in_order[@]}" | grep -qx "$ENABLER_ROLE"; then
      log_error "      '$ENABLER_ROLE' runs, but something is scheduled after it. Whatever"
      log_error "      that is either runs behind an already-active firewall, or adds a"
      log_error "      rule that never reaches it."
    else
      log_error "      '$ENABLER_ROLE' never runs at all, so the rules this playbook adds"
      log_error "      sit staged behind a firewall nobody turns on."
    fi
    log_error "      Keep the '$ENABLER_ROLE' play LAST — see the header of"
    log_error "      ansible/roles/$ENABLER_ROLE/tasks/main.yml for what an interrupted"
    log_error "      run costs when it is not."
    errors=$((errors + 1))
    continue
  fi

  # Applied more than once, the "last" position stops meaning anything: an
  # earlier copy would enable the firewall mid-run, which is the original bug.
  occurrences="$(printf '%s\n' "${roles_in_order[@]}" | grep -cx "$ENABLER_ROLE" || true)"
  if [ "$occurrences" -ne 1 ]; then
    log_error "  $rel — '$ENABLER_ROLE' runs $occurrences times; it must run exactly once, last"
    errors=$((errors + 1))
    continue
  fi

  log_ok "  $rel — ends with '$ENABLER_ROLE'"
done

if [ "$errors" -gt 0 ]; then
  log_error "$errors playbook(s) enable the firewall in the wrong place."
  exit 1
fi

log_ok "Every playbook that adds UFW rules enables the firewall last."
