#!/usr/bin/env bash
# =============================================================================
# check-traefik-image.sh — Verify that the Traefik image actually rendered by
# charts/platform-traefik matches the version that chart is meant to deploy.
#
# Why this check exists: `helm template` alone only validates syntax. It does
# not say *which* image comes out of the render. Yet the proxy version is a
# security decision (advisories GHSA-cxjq <= v3.7.6, GHSA-3ccp <= v3.7.8), and
# the subchart has already had the means to neutralise it silently:
# `versionOverride` froze the version seen by feature-gating, and the
# `traefik.io/proxy-max-version` guard can make the render fall back to the
# chart's own appVersion. A render that "passes" is therefore no proof that we
# deploy the patched version — producing that proof is this script's job.
#
# The reference is the *effective* version (lib/traefik-pin.sh): the
# `traefik.image.tag` pin when one is set, otherwise the vendored subchart's
# appVersion. Since 2026-07-30 there is no pin — upstream caught up — so this
# check now mainly proves that every rendered image agrees with the subchart we
# locked, and that an overlay passed after `--` does not move it.
#
# Usage:
#   scripts/check-traefik-image.sh              # render and verify
#   scripts/check-traefik-image.sh --no-update  # assume charts/ is populated
#   scripts/check-traefik-image.sh -- -f overlay.yaml   # args passed to helm template
#
# The `--` passthrough exists to replay the check against a cluster overlay
# (infra/platform/traefik/values.yaml), which is how it was done by hand until
# now. The reference is always the chart's own effective version, never the
# overlay's — an overlay that moves the image is precisely what this catches.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/traefik-pin.sh
source "$REPO_ROOT/lib/traefik-pin.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

CHART_DIR="$REPO_ROOT/charts/platform-traefik"
UPDATE_DEPS=1
HELM_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-update) UPDATE_DEPS=0; shift ;;
    --) shift; HELM_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

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

  # Dependencies are read by field comparison (lib/chart-deps.sh), not by
  # matching the URL with a regex. The previous version used
  #   /^[[:space:]]*repository:[[:space:]]*https?:\/\//
  # which matches under BSD awk and yielded **nothing** under the runner's awk.
  # No repository was registered, `helm dependency build` then failed with
  # "no repository definition for https://traefik.github.io/charts", and this
  # job had never once passed since it was introduced (2026-07-30, 11e0865).
  n=0
  while IFS=$'\t' read -r _name _version url; do
    case "$url" in
      http://*|https://*) ;;
      *) continue ;;   # oci:// needs no `repo add`
    esac
    n=$((n + 1))
    log_info "helm repo add dep${n} $url"
    helm repo add "dep${n}" "$url" --force-update >/dev/null
  done < <(chart_deps "$CHART_DIR/Chart.yaml" | sort -u -t"$(printf '\t')" -k3,3)

  # Registering nothing is what turned a parsing bug into a cryptic helm error
  # three steps later. If the chart declares an HTTP dependency, it has to have
  # been registered here; silence is the bug, not a valid state.
  if [ "$n" -eq 0 ] && grep -qE 'repository:[[:space:]]*["'"'"']?http' "$CHART_DIR/Chart.yaml"; then
    log_error "$CHART_DIR/Chart.yaml declares an HTTP(S) dependency repository,"
    log_error "but none could be parsed — so none was registered."
    log_error "helm dependency build would fail with 'no repository definition'."
    exit 1
  fi

  log_info "helm dependency build $CHART_DIR"
  helm dependency build "$CHART_DIR" >/dev/null
fi

# ─── Expected tag ───────────────────────────────────────────────────────────
# Resolved *after* the dependency build: with no pin in values.yaml, the
# expected version comes from the subchart tarball, which does not exist before
# that step. An empty answer means the dependency is unresolved — nothing is
# known about the version being shipped, which must never read as a pass.
expected="$(traefik_effective_tag "$CHART_DIR")"

if [ -z "$expected" ]; then
  log_error "Cannot determine the expected Traefik version for $CHART_DIR"
  log_error "No traefik.image.tag in values.yaml, and no subchart tarball matching"
  log_error "the version locked in Chart.lock — run without --no-update."
  exit 1
fi

log_step "Expected tag: $expected"

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
  log_error "The rendered image does not match the version this chart should deploy."
  log_error "Likely cause: the subchart's traefik.io/proxy-max-version guard, or a key"
  log_error "(versionOverride, image.tag) moved by a subchart version bump."
  exit 1
fi

log_ok "Render matches: ${#images[@]} traefik image(s) at $expected"

# ─── README conformance ─────────────────────────────────────────────────────
# The README restates two facts it does not own — the subchart version and the
# proxy version — because a reader needs them at the top of the page, not after
# opening Chart.lock. Restating is fine; restating *without a check* is what let
# the sibling comment in infra/platform/traefik/values.yaml sit wrong for nine
# days. So the copies are verified rather than generated: generating them would
# mean owning a templating step for two table rows, and this repo has already
# decided once that that trade is not worth it (see the umbrella pins).
#
# Only the lines that must track a source are checked. The advisory table below
# them deliberately names older versions (v3.7.6, v3.7.7, v3.7.8) and must not
# be dragged forward.
README="$CHART_DIR/README.md"
locked="$(traefik_locked_field "$CHART_DIR" version)"
doc_errors=0

check_doc_line() {
  local label="$1" pattern="$2" must_contain="$3" line
  line="$(grep -m1 -- "$pattern" "$README" || true)"

  if [ -z "$line" ]; then
    log_error "README: no line matching '$pattern' — did the $label move?"
    doc_errors=$((doc_errors + 1))
    return
  fi

  case "$line" in
    *"$must_contain"*) log_ok "README $label states $must_contain" ;;
    *)
      log_error "README $label is stale — expected $must_contain in:"
      log_error "    $line"
      doc_errors=$((doc_errors + 1))
      ;;
  esac
}

if [ -f "$README" ] && [ -n "$locked" ]; then
  echo ""
  check_doc_line "subchart version" '^| Subchart |'       "$locked"
  check_doc_line "deployed proxy"   '^| Deployed proxy |' "$expected"
  check_doc_line "annotations block" '^# charts/traefik/Chart.yaml (subchart ' "$locked"

  if [ "$doc_errors" -gt 0 ]; then
    echo ""
    log_error "$doc_errors README claim(s) no longer match the chart."
    log_error "Update $README — a bump is not finished until the page agrees."
    exit 1
  fi
fi
