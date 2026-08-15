#!/usr/bin/env bash
# =============================================================================
# check-rendered-images.sh — Verify that every image pin declared in a chart's
# values.yaml actually reaches the rendered manifests.
#
# Two pin shapes are recognised:
#   * `repository:` + `tag:` siblings — the common form, matched exactly.
#   * a bare `tag:` directly under an `image:` mapping, with no `repository:`
#     sibling (`traefik.image.tag`). Generalised on 2026-08-15.
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
# Traefik keeps its own script rather than folding in here, even though the bare
# `image.tag` shape is now understood. check-traefik-image.sh answers a question
# this one cannot: what the *expected* tag is when no pin exists at all, which it
# resolves from the vendored subchart's appVersion. That fallback is the reason
# it stays separate. The overlap is deliberate — this script now also asserts
# traefik's pin reaches the render, which is the half that generalises.
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
    # Bounded by the closing `# ===` rule rather than a line number: the header
    # grows every time this script learns a new pin shape, and a hardcoded range
    # silently starts truncating the help instead of failing.
    -h|--help) awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
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
# Emits one TAB-separated record per pin: "subject<TAB>tag<TAB>kind".
#
#   kind=repo     subject is the pinned repository (`repository:` + `tag:` pair)
#   kind=tagonly  subject is a comma-separated list of ancestor keys used as a
#                 hint, because the pin names no repository to anchor on
#
# For repo pins, indentation is compared so that a `repository:` in one block
# never pairs with a `tag:` from the next one — the two keys must sit at the
# same depth, which is what an `image:` mapping guarantees.
#
# Tag-only pins are emitted ONLY when the tag's immediate parent key is `image`.
# That restriction is the whole reason this stays useful rather than noisy: a
# bare `tag:` is an ordinary word that shows up under `nodeSelector`, chart
# metadata and label blocks, and treating each one as an image pin would invent
# constraints the chart never declared and then fail on them.
#
# The hint is every ancestor key except `image` itself, which carries no
# information. `traefik.image.tag` hints "traefik"; `vault.server.image.tag`
# hints "vault,server", and matching any one of them is enough — subcharts name
# their image after the component about as often as after the chart.
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
    # Deepest tracked key strictly shallower than ind — the parent of that line.
    function parent_key(ind,   i, best) {
      best = -1
      for (i in stack) if (i + 0 < ind && i + 0 > best) best = i + 0
      return best < 0 ? "" : stack[best]
    }
    # Every tracked ancestor of ind except `image`, outermost first.
    function ancestors(ind,   i, n, idx, j, tmp, out) {
      n = 0
      for (i in stack) if (i + 0 < ind) idx[++n] = i + 0
      for (i = 2; i <= n; i++) {          # insertion sort: ancestors are few
        tmp = idx[i]
        for (j = i - 1; j >= 1 && idx[j] > tmp; j--) idx[j + 1] = idx[j]
        idx[j + 1] = tmp
      }
      out = ""
      for (i = 1; i <= n; i++)
        if (stack[idx[i]] != "image")
          out = (out == "" ? stack[idx[i]] : out "," stack[idx[i]])
      return out
    }

    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }

    # Maintain the enclosing-key stack. Runs before the rules below and does not
    # consume the line, so a `tag:` line still reaches its own rule.
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.\/-]*:/ {
      ind = indent($0)
      key = $0; sub(/^[[:space:]]*/, "", key); sub(/:.*$/, "", key)
      for (i in stack) if (i + 0 >= ind) delete stack[i]
      stack[ind] = key
    }

    /^[[:space:]]*repository:[[:space:]]*[^[:space:]#]/ {
      split($0, kv, /repository:/)
      repo = clean(kv[2]); repo_indent = indent($0); next
    }
    /^[[:space:]]*tag:[[:space:]]*[^[:space:]#]/ {
      ti = indent($0)
      split($0, kv, /tag:/)
      tag = clean(kv[2])
      if (repo != "" && ti == repo_indent) {
        print repo "\t" tag "\trepo"
        repo = ""
        next
      }
      if (parent_key(ti) == "image") {
        hints = ancestors(ti)
        if (hints != "") print hints "\t" tag "\ttagonly"
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

  # Every image reference in the render, once. Both pin kinds filter this list.
  mapfile -t rendered_images < <(
    printf '%s\n' "$rendered" |
      sed -n 's|.*image:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$|\1|p' |
      sort -u
  )

  for pin in "${pins[@]}"; do
    IFS=$'\t' read -r subject tag kind <<<"$pin"
    checked=$((checked + 1))

    if [ "$kind" = "repo" ]; then
      # Match the repository as a whole image reference: `<repo>:<tag>`, optionally
      # quoted and optionally registry-qualified. Anchoring on the repository (not
      # a bare tag grep) keeps `hashicorp/vault` from matching `hashicorp/vault-k8s`.
      mapfile -t found < <(
        printf '%s\n' "${rendered_images[@]}" | grep -E "(^|/)${subject}:" || true
      )
      label="$subject:$tag"
    else
      # No repository to anchor on, so anchor on the hint keys instead: keep the
      # rendered images whose LAST path component contains one of them. Comparing
      # only the last component is what keeps a `traefik` hint off
      # `ghcr.io/traefik-labs/other/thing` while still matching `docker.io/traefik`.
      mapfile -t found < <(
        printf '%s\n' "${rendered_images[@]}" |
          awk -v hints="$subject" '
            BEGIN { n = split(tolower(hints), h, /,/) }
            {
              ref = $0
              sub(/:[^:\/]*$/, "", ref)          # strip the tag
              sub(/.*\//, "", ref)               # keep the last path component
              ref = tolower(ref)
              for (i = 1; i <= n; i++) if (index(ref, h[i]) > 0) { print; next }
            }
          '
      )
      label="${subject//,/ or }:$tag (tag-only pin)"
    fi

    if [ "${#found[@]}" -eq 0 ]; then
      log_error "  $label — pinned in values.yaml but absent from the render"
      log_error "      A pin that reaches no manifest is decorative: the subchart"
      log_error "      most likely renamed the key. Find the new path with:"
      log_error "        helm template $chart charts/$chart | grep -n 'image:'"
      errors=$((errors + 1))
      continue
    fi

    if [ "$kind" = "repo" ]; then
      # A repository pin names exactly one image, so EVERY match must carry the tag.
      mismatched=0
      for image in "${found[@]}"; do
        if [ "${image##*:}" != "$tag" ]; then
          log_error "  $image — values.yaml pins tag $tag"
          mismatched=$((mismatched + 1))
        fi
      done
      if [ "$mismatched" -gt 0 ]; then
        errors=$((errors + mismatched))
      else
        log_ok "  $label"
      fi
    else
      # A hint can legitimately match several unrelated images (a chart named
      # `traefik` shipping both `traefik` and a `traefik`-prefixed sidecar), so
      # this asserts only that AT LEAST ONE of them carries the pinned tag. That
      # is deliberately weaker than the repository case — it still catches the
      # failure that matters, a pin whose value reaches nothing — and the
      # alternative, demanding all of them, fails on charts that are correct.
      hit=0
      for image in "${found[@]}"; do
        [ "${image##*:}" = "$tag" ] && hit=1
      done
      if [ "$hit" -eq 1 ]; then
        log_ok "  $label"
      else
        log_error "  $label — no rendered image carries this tag. Candidates:"
        for image in "${found[@]}"; do
          log_error "        $image"
        done
        errors=$((errors + 1))
      fi
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
  log_warn "No image pin (repository+tag, or a bare tag under image:) found in any chart."
  log_warn "That is suspicious rather than clean — this check has nothing to assert."
  exit 1
fi

log_ok "All $checked image pin(s) reach the render ($skipped chart(s) declare none)"
