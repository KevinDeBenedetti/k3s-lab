#!/usr/bin/env bash
# =============================================================================
# check-ansible-collections.sh — Confront the Ansible collections actually
# installed with the versions ansible/requirements.yml pins.
#
# The gap this closes: requirements.yml pins community.general and ansible.posix
# to exact versions, and the `ansible` CI job installs from it — but nothing ever
# checked that the install produced those versions, or produced anything at all.
#
# That matters more than a normal pin drift, because of how the failure presents.
# ansible-lint's `syntax-check` rules are tagged `unskippable`: they cannot be
# turned off in .ansible-lint. When a collection is missing, every task using it
# fails with
#
#     syntax-check[unknown-module]: couldn't resolve module/action
#     'community.general.ufw'. This often indicates a misspelling, missing
#     collection, or incorrect module path.
#
# — which reads as "your playbook is wrong" and sends the reader looking for a
# typo in a file that has not changed. The real cause is a dependency that did
# not install. This script names that cause directly, and is meant to run BEFORE
# ansible-lint so the honest error arrives first.
#
# It also catches the quieter case: a collection present at the WRONG version.
# On a developer machine the ansible package bundles its own collections, and
# those can shadow the pinned ones — `ansible.posix` 2.2.2 from a Homebrew
# ansible sitting in front of the pinned 2.1.0, for instance. Ansible resolves
# the first match in the search path, so that is the version that really runs,
# and it is the one this script compares.
#
# Usage:
#   scripts/check-ansible-collections.sh
#   scripts/check-ansible-collections.sh --requirements path/to/requirements.yml
#
# Env:
#   ANSIBLE_GALAXY  ansible-galaxy command to use (default `ansible-galaxy`) —
#                   injection point for the tests, which must run without a real
#                   collection tree
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"

ANSIBLE_GALAXY="${ANSIBLE_GALAXY:-ansible-galaxy}"
REQUIREMENTS="$REPO_ROOT/ansible/requirements.yml"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --requirements) REQUIREMENTS="$2"; shift 2 ;;
    -h|--help)
      awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -f "$REQUIREMENTS" ] || { log_error "No such requirements file: $REQUIREMENTS"; exit 2; }

command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed"; exit 2; }

# ─── What is pinned ─────────────────────────────────────────────────────────
# "name<TAB>version" per collection. Only entries under `collections:` that
# carry BOTH a name and a version are asserted — a requirement deliberately left
# unpinned is not this script's business to invent a version for.
mapfile -t pinned < <(
  awk '
    /^collections:/            { in_c = 1; next }
    /^[a-z_]+:/                { in_c = 0 }
    !in_c                      { next }
    /^[[:space:]]*-[[:space:]]*name:/ {
      if (name != "" && version != "") print name "\t" version
      name = $NF; version = ""; next
    }
    /^[[:space:]]*version:/    { version = $NF; gsub(/"|'"'"'/, "", version) }
    END { if (name != "" && version != "") print name "\t" version }
  ' "$REQUIREMENTS"
)

if [ "${#pinned[@]}" -eq 0 ]; then
  log_error "No pinned collection found in $REQUIREMENTS."
  log_error "Either the file lists none, or the parser stopped matching its format —"
  log_error "refusing to report success on an assertion that checked nothing."
  exit 2
fi

log_step "${#pinned[@]} collection(s) pinned in ${REQUIREMENTS#"$REPO_ROOT"/}"

# ─── What is installed ──────────────────────────────────────────────────────
if ! installed_json="$("$ANSIBLE_GALAXY" collection list --format json 2>/dev/null)"; then
  log_error "\`$ANSIBLE_GALAXY collection list\` failed — is ansible installed?"
  exit 1
fi

if ! printf '%s' "$installed_json" | jq -e . >/dev/null 2>&1; then
  log_error "\`$ANSIBLE_GALAXY collection list --format json\` did not return JSON."
  exit 1
fi

errors=0

for entry in "${pinned[@]}"; do
  name="${entry%%$'\t'*}"
  want="${entry##*$'\t'}"

  # First match wins, mirroring how ansible itself resolves a collection: the
  # search path is ordered, and a copy earlier in it shadows every later one.
  # `to_entries` preserves the order ansible-galaxy printed.
  got="$(printf '%s' "$installed_json" \
    | jq -r --arg n "$name" '
        [ to_entries[] | .value | select(has($n)) | .[$n].version ] | first // empty
      ')"

  if [ -z "$got" ]; then
    log_error "  $name — pinned at $want, NOT INSTALLED"
    log_error "      ansible-lint will report this as \"couldn't resolve module/action\""
    log_error "      on every task using it. Install it with:"
    log_error "      ansible-galaxy collection install -r ${REQUIREMENTS#"$REPO_ROOT"/}"
    errors=$((errors + 1))
    continue
  fi

  if [ "$got" != "$want" ]; then
    log_error "  $name — pinned at $want, resolves to $got"
    log_error "      That is the copy earliest in the collection search path, so it is"
    log_error "      the one that actually runs. A bundled collection shipped with the"
    log_error "      ansible package can shadow the pinned one this way."
    errors=$((errors + 1))
    continue
  fi

  log_ok "  $name $got"
done

if [ "$errors" -gt 0 ]; then
  log_error "$errors collection(s) do not match ${REQUIREMENTS#"$REPO_ROOT"/}."
  exit 1
fi

log_ok "All ${#pinned[@]} pinned collection(s) are installed at the pinned version."
