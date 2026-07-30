# shellcheck shell=bash
# lib/traefik-pin.sh — Read the pinned Traefik proxy version.
#
# Shared by the two checks that need the same value:
#   scripts/check-traefik-image.sh       — does the render produce this image?
#   scripts/check-traefik-advisories.sh  — is this version vulnerable?
#
# Source this file, then use:
#   traefik_pinned_tag <values.yaml>  → e.g. v3.7.9

# traefik_pinned_tag VALUES_YAML — value of traefik.image.tag in the
# platform-traefik values.yaml. Indentation is honoured so that a `tag:` from
# another section (metrics, hub, …) is never picked up. Prints nothing when the
# pin is absent — callers must treat that silence as an anomaly, not a default:
# without `image.tag`, the subchart silently falls back to its own appVersion.
traefik_pinned_tag() {
  awk '
    /^traefik:/             { root = 1; next }
    root && /^[^[:space:]]/ { root = 0 }
    root && /^  image:/     { img = 1; next }
    img && /^  [^ ]/        { img = 0 }
    img && /^    tag:[[:space:]]*/ { print $2; exit }
  ' "$1"
}
