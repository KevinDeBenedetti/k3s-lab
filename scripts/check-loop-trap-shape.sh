#!/usr/bin/env bash
# =============================================================================
# check-loop-trap-shape.sh — Catch the `[ … ] && cmd` trap at the end of a
# loop body before it ships again.
#
# The trap: with `set -e` (every script here has it), a `for`/`while` loop is
# itself a statement whose exit status is that of the LAST command run in its
# LAST iteration. When that last statement is a bare `[ cond ] && cmd` with no
# `||` fallback, a false `cond` on the final iteration makes the whole loop
# exit non-zero — and the script dies right there, often on the very
# iteration meant to report the interesting case, before any of the intended
# error/warning output runs. It looks like the check crashed, not that it
# found something.
#
# This shipped for real, more than once:
#   - check-deployed-pins.sh (fixed 08f555b): `[ … ] && printf …` inside a
#     `while … | while read` capture — the LAST published tag is never newer
#     than an up-to-date pin, so the trap fired exactly when there was nothing
#     to report. Opened issue #76 (a header with no verdict).
#   - check-inventory-ignored.sh, check-play-order.sh, check-rendered-images.sh,
#     check-umbrella-render.sh carried the same shape (fixed 2026-09-07,
#     alongside this check) — none had tripped yet only because the current
#     data happened to make the last iteration true.
#
# `shellcheck` does not catch this: from its point of view `[ cond ] && cmd`
# is a perfectly ordinary command, and it does not reason about `set -e`
# propagating through a loop's exit status. Hence this grep-shaped check
# instead of relying on shellcheck to grow the rule.
#
# What counts as the trap, deliberately conservative (shape, not full control
# flow — see the false positives it will never flag, below):
#   - a line containing `[ … ] &&` or `[[ … ]] &&`, with no `||` anywhere on
#     the line (an `||` fallback, e.g. `… || continue`, always leaves the
#     line's exit status non-fatal — that is a different, non-silent bug if
#     it is one at all);
#   - that is not itself an `if`/`elif`/`while`/`until` condition (`if [ x ]
#     && [ y ]; then` is a normal, safe condition, not this trap);
#   - immediately followed (skipping blank lines and comments) by a `done`
#     (bare, or with a redirect like `done < file` / `done < <(cmd)`) — i.e.
#     it is the last statement of the loop body.
#
# What this will NOT catch, on purpose: the same shape followed by more loop
# body (not the last statement — a later failure resets $?), or a `[ … ] &&
# cmd` outside any loop (the script's own last line has the same issue in
# principle, but only a loop silently re-triggers it on future data). Fix
# those on sight if you see them; this check only guards the shape that has
# actually bitten us, which the loop case is.
#
# The fix, applied throughout this repo: `if [ cond ]; then cmd; fi` — the `if`
# form still exits non-zero on a false condition, but that is a NORMAL
# `if`-statement's status, not the *loop's own last statement's* status; the
# `for`/`while` compound command that follows exits however its OWN last
# iteration behaves, decoupled from any single comparison inside it.
#
# Usage:
#   scripts/check-loop-trap-shape.sh
#   scripts/check-loop-trap-shape.sh --dir scripts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"

DIRS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) DIRS+=("$2"); shift 2 ;;
    -h|--help)
      awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ "${#DIRS[@]}" -gt 0 ] || DIRS=("scripts" "lib")

log_step "Scanning for the \`[ … ] && cmd\` loop-body trap"

files=()
for d in "${DIRS[@]}"; do
  case "$d" in
    /*) scan_dir="$d" ;;
    *)  scan_dir="$REPO_ROOT/$d" ;;
  esac
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$scan_dir" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)
done

if [ "${#files[@]}" -eq 0 ]; then
  log_error "No .sh files found under: ${DIRS[*]} — that is a bug in this check,"
  log_error "not a clean repository. Refusing to report success on nothing scanned."
  exit 2
fi

hits=0

for f in "${files[@]}"; do
  rel="${f#"$REPO_ROOT"/}"
  hit="$(
    awk '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      { line[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          l = line[i]
          t = trim(l)
          if (t ~ /^#/ || t == "") continue
          if (t ~ /^(if|elif|while|until)[ \t(]/) continue
          if (l ~ /\]\]?[ \t]*&&/ && l !~ /\|\|/) {
            j = i + 1
            while (j <= NR) {
              nt = trim(line[j])
              if (nt == "" || nt ~ /^#/) { j++; continue }
              break
            }
            if (j <= NR && trim(line[j]) ~ /^done([ \t]|$)/) {
              printf "%d: %s\n", i, t
            }
          }
        }
      }
    ' "$f"
  )"
  if [ -n "$hit" ]; then
    log_error "$rel"
    while IFS= read -r line; do
      log_error "    $line"
    done <<< "$hit"
    hits=$((hits + $(printf '%s\n' "$hit" | grep -c .)))
  fi
done

if [ "$hits" -gt 0 ]; then
  log_error ""
  log_error "$hits occurrence(s) of \`[ … ] && cmd\` as the last statement of a loop"
  log_error "body. Rewrite as \`if [ … ]; then cmd; fi\` — see the header of this"
  log_error "script for why the bare form silently kills the script under set -e"
  log_error "the day the last iteration's condition happens to be false."
  exit 1
fi

log_ok "No loop body ends in a bare \`[ … ] && cmd\`."
