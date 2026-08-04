# shellcheck shell=bash
# lib/registry.sh — Read what an OCI registry actually serves.
#
# Extracted from scripts/check-umbrella-pins.sh on 2026-08-04, when a second
# caller appeared: the umbrella asks "are my pins the latest published?", and
# check-deployed-pins.sh asks the same of the ApplicationSet that drives
# production. Same question, same answer, one implementation.
#
# The OCI distribution API is used rather than GitHub's packages API: no token
# is needed for a public package, and it answers the question that actually
# matters — which versions can a consumer resolve today.
# (`gh api /user/packages/...` returned an empty list for a populated package on
# 2026-07-26 — see .github/workflows/cleanup-packages.yml.)
#
# Source this file, then use:
#   registry_tags HOST PATH          → every published tag, one per line
#   registry_tag_created HOST PATH TAG → its publication date (RFC 3339)

# _registry_token HOST PATH — a pull token. Anonymous works for public
# packages; GITHUB_TOKEN is only needed for private ones. Failing to obtain a
# token must abort rather than yield "no tags": callers treat an empty tag list
# as an anomaly, and silently degrading it into "nothing newer exists" is the
# failure mode these checks exist to prevent.
_registry_token() {
  local host="$1" path="$2" auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-u "x:${GITHUB_TOKEN}")
  curl -sSf --max-time 30 "${auth[@]+"${auth[@]}"}" \
    "https://${host}/token?scope=repository:${path}:pull&service=${host}" |
    jq -r '.token // empty'
}

# registry_tags HOST PATH — every tag published for that repository.
registry_tags() {
  local host="$1" path="$2" token
  token="$(_registry_token "$host" "$path")" || return 1
  [ -n "$token" ] || return 1

  curl -sSf --max-time 30 -H "Authorization: Bearer ${token}" \
    "https://${host}/v2/${path}/tags/list" | jq -r '.tags[]? // empty'
}

# registry_tag_created HOST PATH TAG — when that version was pushed, from the
# manifest's `org.opencontainers.image.created` annotation, as RFC 3339.
#
# Prints nothing when the annotation is absent: it is not part of the
# distribution spec, only a convention `helm push` happens to follow. Callers
# must degrade to "no date" rather than treat silence as "just published" —
# a missing date says nothing about staleness.
registry_tag_created() {
  local host="$1" path="$2" tag="$3" token
  token="$(_registry_token "$host" "$path")" || return 0
  [ -n "$token" ] || return 0

  curl -sSf --max-time 30 -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://${host}/v2/${path}/manifests/${tag}" 2>/dev/null |
    jq -r '.annotations["org.opencontainers.image.created"] // empty'
}
