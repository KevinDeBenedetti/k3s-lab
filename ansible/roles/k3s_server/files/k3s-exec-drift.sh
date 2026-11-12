#!/usr/bin/env bash
# =============================================================================
# k3s-exec-drift.sh — does the installed k3s unit run with the arguments the
# role wants?
#
# Run on the node by the k3s_server and k3s_agent roles
# (ansible.builtin.script). The roles pass their flags through INSTALL_K3S_EXEC,
# which only the installer reads, and they used to re-run the installer only
# when the k3s VERSION changed — so a change to k3s_extra_server_args, the
# node IP or the disabled components never reached an installed node, silently.
# This compares what the unit runs with what the role wants; the role re-runs
# the installer (same version) when they differ.
#
# The installer (get.k3s.io, quote_indent) writes one argument per line:
#     ExecStart=/usr/local/bin/k3s \
#         server \
#     	'--node-ip' \
#     	'10.0.0.2' \
#     	…
# single-quoted, with '\'' for a quote inside. An unquoted line is split on
# whitespace, so a hand-written one-line ExecStart is read too.
#
# Compared as MULTISETS: reordering flags in the repo restarts nothing; adding,
# removing or changing one does, and so does repeating one (--kube-apiserver-arg
# is a repeatable flag, so the count matters).
#
# Usage:  K3S_DESIRED_EXEC="server --node-ip … --protect-kernel-defaults" \
#           k3s-exec-drift.sh [unit-file]       (default /etc/systemd/system/k3s.service)
# Output: first line `absent`, `in-sync` or `drift`; on drift, then one line per
#         difference: `+ <arg>` wanted but not running, `- <arg>` running but not wanted.
# Exit:   0 whatever the verdict; 2 on usage error.
# =============================================================================
set -euo pipefail

unit="${1:-/etc/systemd/system/k3s.service}"
if [[ -z "${K3S_DESIRED_EXEC:-}" ]]; then
  echo "k3s-exec-drift: K3S_DESIRED_EXEC is not set" >&2
  exit 2
fi

if [[ ! -f "$unit" ]]; then
  echo absent
  exit 0
fi

# The installer's escape for a quote inside a quoted argument, and the quote.
# Variables, so the unescaping below means the same in every bash: written inline
# as "${t//\'\\\'\'/\'}", bash 3.2 (macOS /bin/bash, which the self-test can run
# under) kept the backslash and turned '\'' into \' instead of '.
ESC_QUOTE="'\\''"
QUOTE="'"

# Tokens of the ExecStart block, binary path first.
tokens=()
inblock=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$inblock" -eq 0 ]]; then
    [[ "$line" == ExecStart=* ]] || continue
    inblock=1
    line="${line#ExecStart=}"
  fi
  cont=0
  if [[ "$line" =~ \\[[:space:]]*$ ]]; then
    cont=1
    line="${line%\\*}"
  fi
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ -n "$line" ]]; then
    if [[ ${#line} -ge 2 && "$line" == \'*\' ]]; then
      t="${line:1:${#line}-2}"
      t=${t//"$ESC_QUOTE"/$QUOTE}
      tokens+=("$t")
    else
      read -r -a words <<<"$line"
      tokens+=("${words[@]}")
    fi
  fi
  [[ "$cont" -eq 1 ]] || break
done <"$unit"

work="$(mktemp -d "${TMPDIR:-/tmp}/k3s-exec-drift.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ ${#tokens[@]} -gt 1 ]]; then
  printf '%s\n' "${tokens[@]:1}" | LC_ALL=C sort >"$work/running"
else
  : >"$work/running"
fi
read -r -a want <<<"$(printf '%s' "$K3S_DESIRED_EXEC" | tr '\n\t' '  ')"
printf '%s\n' "${want[@]}" | LC_ALL=C sort >"$work/wanted"

if cmp -s "$work/running" "$work/wanted"; then
  echo in-sync
  exit 0
fi

echo drift
LC_ALL=C comm -13 "$work/running" "$work/wanted" | sed 's/^/+ /'
LC_ALL=C comm -23 "$work/running" "$work/wanted" | sed 's/^/- /'
