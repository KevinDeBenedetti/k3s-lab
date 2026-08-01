# shellcheck shell=bash
# lib/traefik-pin.sh — Resolve the Traefik proxy version we actually deploy.
#
# Shared by the two checks that need the same value:
#   scripts/check-traefik-image.sh       — does the render produce this version?
#   scripts/check-traefik-advisories.sh  — is this version vulnerable?
#
# Until 2026-07-30 that value was simply `traefik.image.tag`, because the pin was
# always set. It no longer is: subchart 41.1.0 ships appVersion v3.7.9, the very
# version the pin used to force, so the override was dropped. The version is now
# whatever the subchart carries — which is exactly what the subchart's own
# `traefik.proxyVersion` helper resolves:
#
#   versionOverride  →  image.tag  →  subchart .Chart.AppVersion
#
# `traefik_effective_tag` mirrors the last two steps (we forbid the first, see
# charts/platform-traefik/README.md). Mirroring matters: a check that read only
# the pin would go blind the moment the pin disappears, and a check that read
# only the appVersion would miss the day we pin again ahead of upstream.
#
# Source this file, then use:
#   traefik_effective_tag <chart-dir>   → e.g. v3.7.9

# traefik_pinned_tag VALUES_YAML — value of traefik.image.tag in the
# platform-traefik values.yaml. Indentation is honoured so that a `tag:` from
# another section (metrics, hub, …) is never picked up. Prints nothing when no
# pin is set, which is the normal state since 2026-07-30: the absence is a
# fallback to the subchart's appVersion, resolved by traefik_effective_tag.
traefik_pinned_tag() {
  awk '
    /^traefik:/             { root = 1; next }
    root && /^[^[:space:]]/ { root = 0 }
    root && /^  image:/     { img = 1; next }
    img && /^  [^ ]/        { img = 0 }
    img && /^    tag:[[:space:]]*/ { print $2; exit }
  ' "$1"
}

# traefik_locked_field CHART_DIR FIELD — value of FIELD (version, repository) for
# the `traefik` dependency, as recorded in Chart.lock. Chart.lock rather than
# Chart.yaml on purpose: the lock is what `helm dependency build` installs, so it
# is the only file that states which subchart is really in play.
traefik_locked_field() {
  # `key` carries its colon so that the comparison never relies on awk's
  # concatenation-vs-comparison precedence.
  awk -v key="$2:" '
    $1 == "-" && $2 == "name:" { in_dep = ($3 == "traefik"); next }
    /^[^[:space:]]/            { in_dep = 0 }
    in_dep && $1 == key        { print $2; exit }
  ' "$1/Chart.lock"
}

# traefik_subchart_appversion CHART_DIR — appVersion of the traefik subchart
# currently vendored under CHART_DIR/charts/. The tarball is resolved through the
# version in Chart.lock rather than a glob: a leftover tarball from a previous
# bump would otherwise be read as the truth. Prints nothing when the dependency
# has not been fetched yet (`helm dependency build`).
#
# Two layouts are accepted, because the same question gets asked of two kinds of
# chart directory:
#   charts/traefik-<version>.tgz   what `helm dependency build` leaves behind
#   charts/traefik/Chart.yaml      what `helm package` embeds, so what a chart
#                                  pulled back from the registry looks like
# The expanded form carries no version in its path, so its own `version:` is
# checked against Chart.lock before it is trusted — the equivalent of the exact
# filename match that protects the packaged form.
traefik_subchart_appversion() {
  local chart_dir="$1" version tgz dir
  version="$(traefik_locked_field "$chart_dir" version)"
  [ -n "$version" ] || return 0

  tgz="$chart_dir/charts/traefik-$version.tgz"
  if [ -f "$tgz" ]; then
    tar -xzOf "$tgz" traefik/Chart.yaml 2>/dev/null |
      awk '/^appVersion:[[:space:]]*/ { print $2; exit }'
    return 0
  fi

  dir="$chart_dir/charts/traefik/Chart.yaml"
  if [ -f "$dir" ]; then
    local found
    found="$(awk '/^version:[[:space:]]*/ { print $2; exit }' "$dir")"
    [ "$found" = "$version" ] || return 0
    awk '/^appVersion:[[:space:]]*/ { print $2; exit }' "$dir"
  fi
}

# traefik_effective_tag CHART_DIR — the proxy version this chart deploys: the
# pin when one is set, otherwise the vendored subchart's appVersion. Prints
# nothing when neither is available; callers must treat that silence as an
# anomaly, never as "no constraint" — it means the dependency is not resolved,
# so nothing at all is known about the version being shipped.
traefik_effective_tag() {
  local chart_dir="$1" tag
  tag="$(traefik_pinned_tag "$chart_dir/values.yaml")"
  [ -n "$tag" ] || tag="$(traefik_subchart_appversion "$chart_dir")"
  [ -n "$tag" ] || return 0
  printf '%s\n' "$tag"
}
