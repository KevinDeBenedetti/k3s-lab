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

# traefik_locked_field CHART_DIR FIELD — value of FIELD (version, repository)
# for the `traefik` dependency, as recorded in Chart.lock. Generic mechanics in
# lib/subchart.sh (sourced here: the two are inseparable, and every existing
# caller sources only this file).
# shellcheck source=./subchart.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subchart.sh"

traefik_locked_field() {
  subchart_locked_field "$1" traefik "$2"
}

# traefik_subchart_appversion CHART_DIR — appVersion of the traefik subchart
# currently vendored under CHART_DIR/charts/ (both layouts, lock-verified —
# see subchart_appversion in lib/subchart.sh).
traefik_subchart_appversion() {
  subchart_appversion "$1" traefik
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
