# shellcheck shell=bash
# lib/semver.sh — Version comparison and evaluation of the version ranges
# published by the GitHub Security Advisories API (`vulnerable_version_range`,
# e.g. `<= v3.7.8` or `>= v3.7.0, <= v3.7.7`).
#
# Source this file, then use:
#   semver_cmp A B              → prints -1, 0 or 1
#   semver_in_range VER RANGE   → exits 0 if VER falls inside the range
#   semver_latest < versions    → prints the highest of the versions on stdin
#
# The `v` prefix is optional on either side. Pre-release suffixes are
# **truncated** before comparison: `v3.7.0-rc.1` is treated as `v3.7.0`. That is
# deliberate here — we pin stable versions, and treating a pre-release as the
# final version puts us on the cautious side of a vulnerability range. Do not
# reuse these helpers to order pre-releases.
#
# Used by scripts/check-traefik-advisories.sh and
# scripts/check-umbrella-pins.sh.

_semver_field() {
  local v="${1:-0}"
  v="${v//[^0-9]/}"
  printf '%s' "$((10#${v:-0}))"
}

# semver_cmp A B — prints -1 if A < B, 0 if equal, 1 if A > B.
semver_cmp() {
  local a="${1#[vV]}" b="${2#[vV]}"
  a="${a%%-*}"; b="${b%%-*}"
  a="${a%%+*}"; b="${b%%+*}"

  local -a A B
  IFS=. read -r -a A <<<"$a"
  IFS=. read -r -a B <<<"$b"

  local i x y
  for i in 0 1 2; do
    x="$(_semver_field "${A[i]:-0}")"
    y="$(_semver_field "${B[i]:-0}")"
    if [ "$x" -lt "$y" ]; then printf -- '-1\n'; return 0; fi
    if [ "$x" -gt "$y" ]; then printf '1\n'; return 0; fi
  done
  printf '0\n'
}

# semver_in_range VERSION RANGE — exits 0 if VERSION satisfies *every*
# constraint in RANGE (comma-separated, the way GitHub writes them). Exits 1
# otherwise, and 2 when a constraint cannot be parsed — an unknown operator must
# never be read as "not vulnerable".
semver_in_range() {
  local version="$1" range="$2"
  local constraint op bound cmp

  [ -n "$range" ] || return 2

  while IFS= read -r constraint; do
    # trim
    constraint="${constraint#"${constraint%%[![:space:]]*}"}"
    constraint="${constraint%"${constraint##*[![:space:]]}"}"
    [ -n "$constraint" ] || continue

    if [[ "$constraint" =~ ^(\<=|\>=|\<|\>|=)?[[:space:]]*([0-9vV].*)$ ]]; then
      op="${BASH_REMATCH[1]:-=}"
      bound="${BASH_REMATCH[2]}"
    else
      return 2
    fi

    cmp="$(semver_cmp "$version" "$bound")"

    case "$op" in
      '<')  if [ "$cmp" != "-1" ]; then return 1; fi ;;
      '<=') if [ "$cmp" = "1" ];   then return 1; fi ;;
      '>')  if [ "$cmp" != "1" ];  then return 1; fi ;;
      '>=') if [ "$cmp" = "-1" ];  then return 1; fi ;;
      '=')  if [ "$cmp" != "0" ];  then return 1; fi ;;
      *) return 2 ;;
    esac
  done < <(printf '%s\n' "$range" | tr ',' '\n')

  return 0
}

# semver_latest — reads versions on stdin, one per line, prints the highest.
# Anything that is not a bare X.Y.Z (optionally v-prefixed) is **skipped**: a
# registry also serves floating tags like `latest`, and ordering those against
# real versions is meaningless. Pre-releases are skipped too — semver_cmp
# truncates their suffix, so `v1.0.0-rc.1` would compare equal to `v1.0.0` and
# could be reported as the newest published release when it is not.
# Prints nothing on empty input; callers must treat that as an anomaly rather
# than as "nothing newer exists".
semver_latest() {
  local version best=""
  while IFS= read -r version; do
    version="${version#"${version%%[![:space:]]*}"}"
    version="${version%"${version##*[![:space:]]}"}"
    [[ "$version" =~ ^[vV]?[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if [ -z "$best" ] || [ "$(semver_cmp "$version" "$best")" = "1" ]; then
      best="$version"
    fi
  done
  [ -n "$best" ] || return 0
  printf '%s\n' "$best"
}
