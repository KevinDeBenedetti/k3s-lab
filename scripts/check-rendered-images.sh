#!/usr/bin/env bash
# =============================================================================
# check-rendered-images.sh — Verify that every `repository:` + `tag:` image pin
# declared in a chart's values.yaml actually reaches the rendered manifests.
#
# Generalised from check-traefik-image.sh on 2026-08-06 (audit finding 8). That
# script proves one thing for one chart: the image Helm really emits agrees with
# the version the chart claims to deploy. The same question applies to every
# chart that pins an image, and until now only Traefik was asked it.
#
# What this catches: a *decorative* pin — one written in values.yaml that the
# subchart never reads, so it can say 1.21.2 forever while the render emits
# something else. Subcharts rename image keys across major bumps
# (`image.tag` → `server.image.tag`, `image` → `images.*`), and when they do,
# the stale key keeps validating, keeps linting, and silently stops doing
# anything. A pin that matches nothing in the render is therefore treated as a
# failure here, not as "nothing to check".
#
# ⚠️ What this does NOT catch: cluster drift. A pin can be honoured by the render
# and still not be what runs, because the infra `platform-vault` Application is
# multi-source and layers `$values/platform/vault/values.yaml` on top. That is a
# different question with a different answer — scripts/check-deployed-charts.sh
# and check-deployed-pins.sh own it, and they need cluster access this script
# deliberately does not want. Keep the two apart: this one must stay offline so
# it can run on every PR.
#
# Traefik keeps its own script rather than folding in here. Its pin is a bare
# `image.tag` with no `repository:`, and its expected value falls back to the
# vendored subchart's appVersion when the pin is absent — Traefik-specific logic
# that would only dilute this check.
#
# Usage:
#   scripts/check-rendered-images.sh                    # all charts
#   scripts/check-rendered-images.sh platform-vault     # one or more charts
#   scripts/check-rendered-images.sh --no-update        # assume charts/ populated
#   scripts/check-rendered-images.sh --charts-dir DIR   # look for charts under DIR
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=../lib/chart-deps.sh
source "$REPO_ROOT/lib/chart-deps.sh"

UPDATE_DEPS=1
CHARTS_DIR="$REPO_ROOT/charts"
CHARTS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-update) UPDATE_DEPS=0; shift ;;
    --charts-dir) CHARTS_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) log_error "Unknown option: $1"; exit 2 ;;
    *) CHARTS+=("$1"); shift ;;
  esac
done

if [ "${#CHARTS[@]}" -eq 0 ]; then
  for d in "$CHARTS_DIR"/*/; do
    [ -d "$d" ] || continue
    CHARTS+=("$(basename "$d")")
  done
fi

# ─── Pin extraction ─────────────────────────────────────────────────────────
# Emits "repository<TAB>tag" for each adjacent repository/tag pair in a
# values.yaml. Indentation is compared so that a `repository:` in one block
# never pairs with a `tag:` from the next one — the two keys must sit at the
# same depth, which is what an `image:` mapping guarantees.
#
# Comments are stripped and quotes removed, because `tag: "1.32"` and
# `tag: 1.32` mean the same thing to Helm and must compare equal here.
chart_image_pins() {
  awk '
    function indent(line,   n) { match(line, /^[[:space:]]*/); return RLENGTH }
    function clean(v) {
      sub(/[[:space:]]*#.*$/, "", v)
      gsub(/^[[:space:]]*["'"'"']?|["'"'"']?[[:space:]]*$/, "", v)
      return v
    }
    /^[[:space:]]*repository:[[:space:]]*[^[:space:]#]/ {
      split($0, kv, /repository:/)
      repo = clean(kv[2]); repo_indent = indent($0); next
    }
    /^[[:space:]]*tag:[[:space:]]*[^[:space:]#]/ {
      if (repo != "" && indent($0) == repo_indent) {
        split($0, kv, /tag:/)
        print repo "\t" clean(kv[2])
        repo = ""
      }
      next
    }
    # Any key shallower than the pending repository closes its block.
    /^[[:space:]]*[A-Za-z_-]+:/ { if (repo != "" && indent($0) < repo_indent) repo = "" }
  ' "$1"
}

# ─── Dependency resolution ──────────────────────────────────────────────────
# Same reasoning as check-traefik-image.sh: `helm dependency build` resolves
# Chart.lock against *registered* repos and fails with "no repository
# definition" on a fresh runner, so register them first. `build` rather than
# `update` so the check validates the version this repo committed, not whatever
# upstream serves today. A throwaway HELM_REPOSITORY_CONFIG keeps the caller's
# own `helm repo list` untouched.
helm_home=""
if [ "$UPDATE_DEPS" -eq 1 ]; then
  helm_home="$(mktemp -d "${TMPDIR:-/tmp}/rendered-image-check.XXXXXX")"
  trap 'rm -rf "$helm_home"' EXIT
  export HELM_REPOSITORY_CONFIG="$helm_home/repositories.yaml"
  export HELM_REPOSITORY_CACHE="$helm_home/cache"
fi

errors=0
checked=0
skipped=0

for chart in "${CHARTS[@]}"; do
  chart_dir="$CHARTS_DIR/$chart"
  values="$chart_dir/values.yaml"

  [ -f "$chart_dir/Chart.yaml" ] || continue
  [ -f "$values" ] || continue

  mapfile -t pins < <(chart_image_pins "$values")
  if [ "${#pins[@]}" -eq 0 ]; then
    skipped=$((skipped + 1))
    continue
  fi

  log_step "$chart — ${#pins[@]} image pin(s)"

  if [ "$UPDATE_DEPS" -eq 1 ]; then
    n=0
    while IFS=$'\t' read -r _name _version url; do
      case "$url" in
        http://*|https://*) ;;
        *) continue ;;   # oci:// needs no `repo add`
      esac
      n=$((n + 1))
      helm repo add "${chart}-dep${n}" "$url" --force-update >/dev/null
    done < <(chart_deps "$chart_dir/Chart.yaml" | sort -u -t"$(printf '\t')" -k3,3)

    helm dependency build "$chart_dir" >/dev/null 2>&1 || {
      log_error "$chart — helm dependency build failed"
      errors=$((errors + 1))
      continue
    }
  fi

  if ! rendered="$(helm template "$chart" "$chart_dir" 2>&1)"; then
    log_error "$chart — helm template failed:"
    printf '%s\n' "$rendered" | sed 's/^/    /' | head -20
    errors=$((errors + 1))
    continue
  fi

  for pin in "${pins[@]}"; do
    IFS=$'\t' read -r repo tag <<<"$pin"
    checked=$((checked + 1))

    # Match the repository as a whole image reference: `<repo>:<tag>`, optionally
    # quoted and optionally registry-qualified. Anchoring on the repository (not
    # a bare tag grep) keeps `hashicorp/vault` from matching `hashicorp/vault-k8s`.
    mapfile -t found < <(
      printf '%s\n' "$rendered" |
        sed -n 's|.*image:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$|\1|p' |
        grep -E "(^|/)${repo}:" || true
    )

    if [ "${#found[@]}" -eq 0 ]; then
      log_error "  $repo:$tag — pinned in values.yaml but absent from the render"
      log_error "      A pin that reaches no manifest is decorative: the subchart"
      log_error "      most likely renamed the key. Find the new path with:"
      log_error "        helm template $chart charts/$chart | grep -n 'image:'"
      errors=$((errors + 1))
      continue
    fi

    mismatched=0
    for image in $(printf '%s\n' "${found[@]}" | sort -u); do
      if [ "${image##*:}" != "$tag" ]; then
        log_error "  $image — values.yaml pins tag $tag"
        mismatched=$((mismatched + 1))
      fi
    done

    if [ "$mismatched" -gt 0 ]; then
      errors=$((errors + mismatched))
    else
      log_ok "  $repo:$tag"
    fi
  done
done

echo ""

if [ "$errors" -gt 0 ]; then
  log_error "$errors image pin(s) do not match the render."
  log_error "Either the pin is stale, or the subchart moved the key it lives under."
  exit 1
fi

if [ "$checked" -eq 0 ]; then
  log_warn "No repository+tag image pin found in any chart."
  log_warn "That is suspicious rather than clean — this check has nothing to assert."
  exit 1
fi

log_ok "All $checked image pin(s) reach the render ($skipped chart(s) declare none)"
