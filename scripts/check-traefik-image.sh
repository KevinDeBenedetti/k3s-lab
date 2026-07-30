#!/usr/bin/env bash
# =============================================================================
# check-traefik-image.sh — Verify that the Traefik image actually rendered by
# charts/platform-traefik matches the tag pinned in its values.yaml.
#
# Why this check exists: `helm template` alone only validates syntax. It does
# not say *which* image comes out of the render. Yet the `traefik.image.tag` pin
# is a security decision (advisories GHSA-cxjq <= v3.7.6, GHSA-3ccp <= v3.7.8),
# and the subchart has already had the means to neutralise it silently:
# `versionOverride` froze the version seen by feature-gating, and the
# `traefik.io/proxy-max-version` guard can make the render fall back to the
# chart's own appVersion. A render that "passes" is therefore no proof that we
# deploy the patched version — producing that proof is this script's job.
#
# Usage:
#   scripts/check-traefik-image.sh              # render and verify
#   scripts/check-traefik-image.sh --no-update  # assume charts/ is populated
#   scripts/check-traefik-image.sh -- -f overlay.yaml   # args passed to helm template
#
# The `--` passthrough exists to replay the check against a cluster overlay
# (infra/platform/traefik/values.yaml), which is how it was done by hand until
# now. The reference is always the pin in the chart's own values.yaml.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/traefik-pin.sh
source "$REPO_ROOT/lib/traefik-pin.sh"

CHART_DIR="$REPO_ROOT/charts/platform-traefik"
VALUES="$CHART_DIR/values.yaml"
UPDATE_DEPS=1
HELM_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-update) UPDATE_DEPS=0; shift ;;
    --) shift; HELM_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

# ─── Expected tag ───────────────────────────────────────────────────────────
expected="$(traefik_pinned_tag "$VALUES")"

if [ -z "$expected" ]; then
  log_error "No traefik.image.tag in $VALUES"
  log_error "The pin is a security decision: do not drop it without updating this script."
  exit 1
fi

log_step "Expected tag: $expected"

# ─── Render ─────────────────────────────────────────────────────────────────
if [ "$UPDATE_DEPS" -eq 1 ]; then
  # `helm dependency build` resolves Chart.lock against the *registered* repos,
  # and fails with "no repository definition for <url>" when a dependency's
  # repository is unknown — which is exactly the state of a fresh CI runner.
  # So register them first.
  #
  # `helm dependency update` would sidestep the registration, but it re-resolves
  # and rewrites Chart.lock: the check would then validate whatever the upstream
  # repo serves today rather than the version this repo committed. For a pin
  # whose whole point is reproducibility, `build` is the right verb.
  #
  # The repos are registered in a throwaway helm config so that running this
  # script never mutates the caller's own `helm repo list`.
  # Explicit template: BSD mktemp (macOS) ignores TMPDIR for the bare `-d` form
  # and goes through confstr instead, which GNU mktemp does not.
  helm_home="$(mktemp -d "${TMPDIR:-/tmp}/traefik-image-check.XXXXXX")"
  trap 'rm -rf "$helm_home"' EXIT
  export HELM_REPOSITORY_CONFIG="$helm_home/repositories.yaml"
  export HELM_REPOSITORY_CACHE="$helm_home/cache"

  n=0
  while read -r url; do
    [ -n "$url" ] || continue
    n=$((n + 1))
    log_info "helm repo add dep${n} $url"
    helm repo add "dep${n}" "$url" --force-update >/dev/null
  done < <(
    awk '
      /^dependencies:/ { deps = 1; next }
      deps && /^[^[:space:]-]/ { deps = 0 }
      deps && /^[[:space:]]*repository:[[:space:]]*https?:\/\// { print $NF }
    ' "$CHART_DIR/Chart.yaml" | sort -u
  )

  log_info "helm dependency build $CHART_DIR"
  helm dependency build "$CHART_DIR" >/dev/null
fi

rendered="$(helm template platform-traefik "$CHART_DIR" ${HELM_ARGS[@]+"${HELM_ARGS[@]}"})"

# ─── Verification ───────────────────────────────────────────────────────────
# Only the proxy's own images are considered: the chart may ship others (hub,
# init containers) that are not bound to this pin.
mapfile -t images < <(
  printf '%s\n' "$rendered" |
    sed -n 's|.*image:[[:space:]]*"\{0,1\}\([^"]*traefik:[^"[:space:]]*\).*|\1|p' |
    sort -u
)

if [ "${#images[@]}" -eq 0 ]; then
  log_error "No traefik image in the render — does the chart still produce a workload?"
  log_error "An empty render must never count as a success."
  exit 1
fi

errors=0
for image in "${images[@]}"; do
  tag="${image##*:}"
  if [ "$tag" = "$expected" ]; then
    log_ok "$image"
  else
    log_error "$image — expected tag $expected"
    errors=$((errors + 1))
  fi
done

echo ""

if [ "$errors" -gt 0 ]; then
  log_error "The rendered image does not match the security pin in values.yaml."
  log_error "Likely cause: the subchart's traefik.io/proxy-max-version guard, or a key"
  log_error "(versionOverride, image.tag) moved by a subchart version bump."
  exit 1
fi

log_ok "Render matches the pin: ${#images[@]} traefik image(s) at $expected"
