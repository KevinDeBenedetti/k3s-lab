# shellcheck shell=bash
# lib/log.sh — Shared logging helpers for infra scripts.
# Source this file at the top of any script:
#   source "$(dirname "$0")/../lib/log.sh"
#
# Mirrors dotfiles/os/helpers/log.sh for consistency across repos.

_red='\e[0;31m'
_green='\e[0;32m'
_yellow='\e[1;33m'
_cyan='\e[0;36m'
_nc='\033[0m'

# log_step LABEL  — numbered section header (e.g. "[1/4] Namespaces...")
log_step()  { printf "\n${_cyan}▶${_nc} %s\n" "${*}"; }
# log_info MSG    — plain informational line
log_info()  { printf "${_cyan}[info]${_nc}  %s\n" "${*}"; }
# log_ok MSG      — success (✅)
log_ok()    { printf "${_green}✅${_nc} %s\n" "${*}"; }
# log_warn MSG    — warning (⚠️)
log_warn()  { printf "${_yellow}⚠️  ${_nc}%s\n" "${*}"; }
# log_error MSG   — error (❌), does NOT exit — caller decides
log_error() { printf "${_red}❌${_nc} %s\n" "${*}"; }
