#!/usr/bin/env bash
# =============================================================================
# check-inventory-ignored.sh — Prove the generated Ansible inventory can never
# be committed.
#
# What is at stake: scripts/generate-inventory.sh writes the nodes' public AND
# private IPs into ansible/inventory/. Until 2026-08-19 nothing ignored that
# path — .gitignore's only Ansible entry was `ansible/*.retry`. The files were
# therefore *untracked but not ignored*, which is the worst of both: invisible
# to every check in this repo, and one `git add -A` away from being published.
#
# Two assertions, because either alone gives a false sense of safety:
#
#   1. Nothing under the inventory is TRACKED. Catches the accident that already
#      happened — a file committed before the ignore rule existed. `.gitignore`
#      does not apply retroactively: once a path is tracked, git keeps tracking
#      it and every ignore rule is silently bypassed.
#
#   2. The ignore rules still MATCH. Catches the quieter regression: someone
#      reorganises .gitignore, or the generator starts writing elsewhere, and the
#      rule keeps existing while protecting nothing. This is checked with
#      `git check-ignore` on paths that need not exist, so it works on a fresh
#      clone.
#
# The guarded paths are cross-checked against generate-inventory.sh rather than
# trusted: if that script starts writing somewhere else, this fails loudly
# instead of guarding a path nobody writes any more.
#
# Usage:
#   scripts/check-inventory-ignored.sh
#   scripts/check-inventory-ignored.sh --repo /path/to/checkout
#
# Env:
#   GIT  git command to use (default `git`) — injection point for the tests
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$DEFAULT_ROOT/lib/log.sh"

GIT="${GIT:-git}"
REPO_ROOT="$DEFAULT_ROOT"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    -h|--help)
      awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -d "$REPO_ROOT" ] || { log_error "No such directory: $REPO_ROOT"; exit 2; }

# Paths that must never reach a commit. Relative to the repository root.
GUARDED=(
  "ansible/inventory/hosts.yml"
  "ansible/inventory/group_vars/all.yml"
)

log_step "Inventory must be unreachable from a commit"

errors=0

# ─── Cross-check: does the generator still write where we guard? ────────────
# A guard aimed at a path nobody writes protects nothing, and would keep
# reporting success forever. Skipped when the generator is absent (the --repo
# fixtures used by the tests have no scripts/ tree).
generator="$REPO_ROOT/scripts/generate-inventory.sh"
if [ -f "$generator" ]; then
  mapfile -t written < <(
    sed -n 's/.*="\${ANSIBLE_DIR}\/\([^"]*\)".*/ansible\/\1/p' "$generator"
  )
  if [ "${#written[@]}" -eq 0 ]; then
    log_error "Could not read any inventory path out of generate-inventory.sh."
    log_error "That is a bug in this check, not a clean repository — refusing to"
    log_error "report success on an assertion that verified nothing."
    exit 2
  fi
  for path in "${written[@]}"; do
    covered=0
    for guarded in "${GUARDED[@]}"; do
      [ "$path" = "$guarded" ] && covered=1 && break
    done
    if [ "$covered" -eq 0 ]; then
      log_error "  generate-inventory.sh writes '$path', which this check does not guard"
      log_error "      Add it to GUARDED in $(basename "${BASH_SOURCE[0]}"), and to .gitignore."
      errors=$((errors + 1))
    fi
  done
fi

# ─── 1. Nothing tracked ─────────────────────────────────────────────────────
tracked="$("$GIT" -C "$REPO_ROOT" ls-files -- 'ansible/inventory' 'ansible/inventory/**' 2>/dev/null || true)"
if [ -n "$tracked" ]; then
  log_error "  Inventory files are TRACKED by git:"
  printf '%s\n' "$tracked" | sed 's/^/        /'
  log_error "      .gitignore does not apply to already-tracked files. Untrack them:"
  log_error "        git rm --cached -r ansible/inventory"
  log_error "      Then rotate anything they exposed — the IPs are in the history."
  errors=$((errors + 1))
else
  log_ok "  no inventory file is tracked"
fi

# ─── 2. The ignore rules still match ────────────────────────────────────────
for path in "${GUARDED[@]}"; do
  if "$GIT" -C "$REPO_ROOT" check-ignore -q "$path" 2>/dev/null; then
    log_ok "  ignored: $path"
  else
    log_error "  NOT ignored: $path"
    log_error "      The file would show up as untracked and could be added by"
    log_error "      \`git add -A\`. Restore the rule in .gitignore:"
    log_error "        ansible/inventory/"
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  log_error "$errors problem(s): the generated inventory is not safe from a commit."
  exit 1
fi

log_ok "The generated inventory is ignored and untracked."
