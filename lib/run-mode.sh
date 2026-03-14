# lib/run-mode.sh — Dual-mode execution preamble for k3s-lab scripts.
#
# Source this file at the very top of any script (after set -euo pipefail):
#
#   K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"
#   # shellcheck source=lib/run-mode.sh
#   source "$(dirname "${BASH_SOURCE[0]:-run-mode.sh}")/../lib/run-mode.sh"
#
# Why this exists
# ───────────────
# Scripts can be executed in two ways:
#   LOCAL  — `bash /path/to/script.sh`  (BASH_SOURCE[0] is a real file)
#   REMOTE — `bash <(curl -fsSL ...)`   (BASH_SOURCE[0] is /dev/fd/NN — a pipe)
#
# In remote mode the usual "cd $(dirname ${BASH_SOURCE[0]})" trick fails because
# /dev/fd/NN is not a directory.  This preamble detects the mode and exposes
# three helper functions that transparently resolve paths in either case.
#
# Exposed helpers
# ───────────────
#   _lib  <name>        Source a file from lib/ (e.g. _lib log.sh)
#   _k8s  <rel-path>    Echo an absolute path or URL to a kubernetes/ manifest
#                       (safe to pass to `kubectl apply -f`)
#   _helm_val <rel-path> Echo a local path to a helm values file; in remote
#                        mode the file is downloaded to a temp path first.
#                        Temp files are cleaned up automatically on EXIT.
#
# Prerequisites
# ─────────────
#   K3S_LAB_RAW must be set before sourcing this file (or it defaults to main).
# ──────────────────────────────────────────────────────────────────────────────

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"

# Detect execution context.
_run_src="${BASH_SOURCE[1]:-}"   # [1] = the script that sourced us
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  _RUN_REPO="$(cd "$(dirname "${_run_src}")/.." && pwd)"
  _RUN_REMOTE=0
else
  # Could also be triggered when K3S_LAB is explicitly empty (remote mode).
  _RUN_REPO=""
  _RUN_REMOTE=1
fi

# Also allow K3S_LAB env var to override — set by the local-mode Make macro.
if [[ -n "${K3S_LAB:-}" ]]; then
  _RUN_REPO="${K3S_LAB}"
  _RUN_REMOTE=0
fi

# _lib <name>
# Source a helper from lib/. Local: from disk. Remote: streamed via curl.
_lib() {
  local name="$1"
  if [[ "${_RUN_REMOTE}" -eq 0 ]]; then
    # shellcheck disable=SC1090
    source "${_RUN_REPO}/lib/${name}"
  else
    # shellcheck disable=SC1090
    source <(curl -fsSL "${K3S_LAB_RAW}/lib/${name}")
  fi
}

# _k8s <rel-path>
# Return the path (or URL) to a kubernetes/ manifest.
# Local:  absolute filesystem path  → kubectl apply -f, helm --values, etc.
# Remote: raw GitHub URL            → kubectl apply -f supports URLs natively.
_k8s() {
  if [[ "${_RUN_REMOTE}" -eq 0 ]]; then
    echo "${_RUN_REPO}/kubernetes/$1"
  else
    echo "${K3S_LAB_RAW}/kubernetes/$1"
  fi
}

# _k8s_file <rel-path>
# Return a local filesystem path to any kubernetes/ file.
# Local:  absolute filesystem path (no download needed).
# Remote: download to a temp file and return its path.
#         All temp files are registered for cleanup on EXIT.
#
# Use this (not _k8s) when you need a real file on disk:
#   helm upgrade --values "$(_k8s_file ingress/traefik-values.yaml)"
#   envsubst < "$(_k8s_file cert-manager/clusterissuer.yaml)" | kubectl apply -f -
_run_tmp_files=()
_k8s_file() {
  if [[ "${_RUN_REMOTE}" -eq 0 ]]; then
    echo "${_RUN_REPO}/kubernetes/$1"
  else
    local tmpf
    tmpf="$(mktemp /tmp/k8s-file-XXXXXXXX.yaml)"
    _run_tmp_files+=("${tmpf}")
    curl -fsSL "${K3S_LAB_RAW}/kubernetes/$1" -o "${tmpf}"
    echo "${tmpf}"
  fi
}

# Register cleanup of any temp files created by _helm_val.
_run_mode_cleanup() {
  [[ "${#_run_tmp_files[@]}" -gt 0 ]] && rm -f "${_run_tmp_files[@]}" 2>/dev/null || true
}
trap _run_mode_cleanup EXIT
