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
#   _k8s_file <rel-path> Echo a local path to a kubernetes/ file; in remote
#                        mode the file is downloaded to a shared temp directory.
#                        The temp directory is cleaned up automatically on EXIT.
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
# Remote: download into a shared temp directory and return the path.
#         The temp directory is created once in the main shell so the EXIT trap
#         can clean it up reliably — even though callers use $() subshells.
#
# Use this (not _k8s) when you need a real file on disk:
#   helm upgrade --values "$(_k8s_file ingress/traefik-values.yaml)"
#   envsubst < "$(_k8s_file cert-manager/clusterissuer.yaml)" | kubectl apply -f -
#
# macOS note: BSD mktemp requires X's at the very end of the template (no suffix).
# Using a directory sidesteps the issue entirely — files are named by their path.
if [[ "${_RUN_REMOTE}" -eq 1 ]]; then
  _run_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/k8s-XXXXXXXX")"
else
  _run_tmp_dir=""
fi

_k8s_file() {
  if [[ "${_RUN_REMOTE}" -eq 0 ]]; then
    echo "${_RUN_REPO}/kubernetes/$1"
  else
    # Flatten the relative path to a safe filename (e.g. ingress/foo.yaml → ingress-foo.yaml)
    local dst
    dst="${_run_tmp_dir}/$(echo "$1" | tr '/' '-')"
    curl -fsSL "${K3S_LAB_RAW}/kubernetes/$1" -o "${dst}"
    echo "${dst}"
  fi
}

# Cleanup: remove the shared temp directory on script exit.
_run_mode_cleanup() {
  [[ -n "${_run_tmp_dir:-}" ]] && rm -rf "${_run_tmp_dir}" 2>/dev/null || true
}
trap _run_mode_cleanup EXIT
