# shellcheck shell=bash
# lib/subchart.sh — Read a named subchart's identity out of a chart directory.
#
# Generalized from lib/traefik-pin.sh on 2026-08-03, when the deployed watch
# grew beyond Traefik: the "which version of its wrapped component does this
# chart actually ship" question is the same for platform-cert-manager and
# platform-external-secrets, only the subchart name changes. traefik-pin.sh
# keeps its API (and its pin-awareness, which is Traefik-specific) and
# delegates the generic part here.
#
# Source this file, then use:
#   subchart_locked_field <chart-dir> <name> <field>  → e.g. 41.1.0
#   subchart_appversion <chart-dir> <name>            → e.g. v3.7.9

# subchart_locked_field CHART_DIR NAME FIELD — value of FIELD (version,
# repository) for the NAME dependency, as recorded in Chart.lock. Chart.lock
# rather than Chart.yaml on purpose: the lock is what `helm dependency build`
# installs, so it is the only file that states which subchart is really in
# play.
subchart_locked_field() {
  # `key` carries its colon so that the comparison never relies on awk's
  # concatenation-vs-comparison precedence.
  awk -v want="$2" -v key="$3:" '
    $1 == "-" && $2 == "name:" { in_dep = ($3 == want); next }
    /^[^[:space:]]/            { in_dep = 0 }
    in_dep && $1 == key        { print $2; exit }
  ' "$1/Chart.lock"
}

# subchart_appversion CHART_DIR NAME — appVersion of the NAME subchart
# currently vendored under CHART_DIR/charts/. The tarball is resolved through
# the version in Chart.lock rather than a glob: a leftover tarball from a
# previous bump would otherwise be read as the truth. Prints nothing when the
# dependency has not been fetched yet (`helm dependency build`).
#
# Two layouts are accepted, because the same question gets asked of two kinds
# of chart directory:
#   charts/NAME-<version>.tgz   what `helm dependency build` leaves behind
#   charts/NAME/Chart.yaml      what `helm package` embeds, so what a chart
#                               pulled back from the registry looks like
# The expanded form carries no version in its path, so its own `version:` is
# checked against Chart.lock before it is trusted — the equivalent of the
# exact filename match that protects the packaged form.
subchart_appversion() {
  local chart_dir="$1" name="$2" version tgz dir
  version="$(subchart_locked_field "$chart_dir" "$name" version)"
  [ -n "$version" ] || return 0

  tgz="$chart_dir/charts/$name-$version.tgz"
  if [ -f "$tgz" ]; then
    tar -xzOf "$tgz" "$name/Chart.yaml" 2>/dev/null |
      awk '/^appVersion:[[:space:]]*/ { print $2; exit }'
    return 0
  fi

  dir="$chart_dir/charts/$name/Chart.yaml"
  if [ -f "$dir" ]; then
    local found
    found="$(awk '/^version:[[:space:]]*/ { print $2; exit }' "$dir")"
    [ "$found" = "$version" ] || return 0
    awk '/^appVersion:[[:space:]]*/ { print $2; exit }' "$dir"
  fi
}
