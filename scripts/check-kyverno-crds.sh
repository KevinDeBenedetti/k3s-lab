#!/usr/bin/env bash
# =============================================================================
# check-kyverno-crds.sh — Confront the Kyverno policies charts/platform-security
# renders with what the cluster can actually accept.
#
# The gap this closes (audit finding 1, "add a live check in the spirit of the
# existing Traefik jobs"): flipping `kyvernoPolicies.enabled: true` emits six
# `kyverno.io/v1 ClusterPolicy` manifests. If the CRD backing them is absent, or
# present but no longer serving v1, the Application does not degrade — it fails
# to sync outright with `no matches for kind "ClusterPolicy"`. Everything else in
# this repo is satisfied long before that point: the chart lints, the render is
# valid YAML, and platform-security-render.bats proves the six policies exist as
# manifests. None of them can see a cluster, so none of them can tell whether the
# manifests are installable there. That is the whole question this script asks.
#
# It also asks the second half, which the rollout learned the hard way: a policy
# that renders and is installable can still be absent from the cluster because
# something upstream refused it. On 2026-08-13 the ArgoCD AppProject `platform`
# did not list `kyverno.io/ClusterPolicy` in its clusterResourceWhitelist, so all
# six were rejected at sync for 32h while the Application sat `OutOfSync`/
# `Healthy` — green enough to miss. `--crds-only` skips both halves below when
# you only want the installability question.
#
# And a third, added 2026-09-07: a policy PRESENT in the cluster can still be
# enforcing the wrong thing — an out-of-sync Application, a `kubectl edit`, or
# the 2026-08-20 `validationFailureAction` alias removal that motivated this
# very check. That removal was precisely undetectable if it had gone wrong: a
# consumer left on the dead alias would silently fall back to the chart default
# (`Audit`), and on any install that was already `Audit` the render, the CRD,
# and "does the object exist" all stay green — nothing before this checked what
# the live object actually enforces. This reads `spec.rules[].validate.
# failureAction` off each policy already confirmed to exist and compares it,
# rule by rule, against what the render says it should be.
#
# What is asserted comes from the RENDER, not from re-reading the values gates:
# if no policy renders (kyverno.enabled=false, or kyvernoPolicies.enabled=false)
# there is nothing to install and nothing to check, and saying so is the honest
# answer rather than a hardcoded skip that drifts from the chart. Same reasoning
# for the failureAction comparison: the expected value comes from parsing what
# `helm template` actually emitted, not from re-reading `kyvernoPolicies.
# failureAction` a second time.
#
# ⚠️ Needs cluster access, so it is NOT part of the offline PR checks — same
# split as check-deployed-charts.sh. scripts/check-rendered-images.sh and
# tests/bats/platform-security-render.bats own the offline half.
#
# Usage:
#   scripts/check-kyverno-crds.sh
#   scripts/check-kyverno-crds.sh --chart charts/platform-security
#   scripts/check-kyverno-crds.sh --values /path/to/infra/platform/security/values.yaml
#   scripts/check-kyverno-crds.sh --crds-only
#
# Env:
#   KUBECONFIG  standard
#   KUBECTL     kubectl command to use (default `kubectl`) — injection point for
#               the tests, which must run without a cluster
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"

KUBECTL="${KUBECTL:-kubectl}"
CHART_DIR="$REPO_ROOT/charts/platform-security"
CRDS_ONLY=0
VALUES_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart)      CHART_DIR="$2"; shift 2 ;;
    --values)     VALUES_ARGS+=(--values "$2"); shift 2 ;;
    --crds-only)  CRDS_ONLY=1; shift ;;
    -h|--help)
      awk 'NR > 1 { if (/^# ={10,}/) { if (++rule == 2) exit; next } sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

[ -d "$CHART_DIR" ] || { log_error "No such chart directory: $CHART_DIR"; exit 2; }

# ─── Render ─────────────────────────────────────────────────────────────────
# The chart is copied and its `dependencies:` block dropped before rendering,
# for the same reason tests/bats/platform-security-render.bats does it:
# `charts/**/charts/*.tgz` is gitignored, so the vendored subcharts exist only on
# a machine that has run `helm dependency build`. The policies live in this
# chart's own templates/, so they render with no subchart present and no network.
# Rendering in place would make this script pass or fail on whether someone
# happened to have built dependencies locally.
workdir="$(mktemp -d "${TMPDIR:-/tmp}/kyverno-crd-check.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

chart="$workdir/chart"
cp -R "$CHART_DIR" "$chart"
rm -rf "$chart/charts" "$chart/Chart.lock"
awk '/^dependencies:/{exit} {print}' "$CHART_DIR/Chart.yaml" > "$chart/Chart.yaml"
grep -q '^name:' "$chart/Chart.yaml" || { log_error "Stripped Chart.yaml lost its name — refusing to render"; exit 2; }

if ! rendered="$(helm template ps "$chart" "${VALUES_ARGS[@]+"${VALUES_ARGS[@]}"}" 2>&1)"; then
  log_error "helm template failed:"
  printf '%s\n' "$rendered" | sed 's/^/    /' | head -20
  exit 1
fi

# "apiVersion<TAB>kind<TAB>name" for each Kyverno document this chart owns.
# Scoped by `# Source:` so a subchart's objects can never be attributed here.
mapfile -t policies < <(
  printf '%s\n' "$rendered" | awk '
    /^# Source: .*\/templates\/kyverno-policies\// { keep = 1; next }
    /^# Source: /                                  { keep = 0; next }
    keep && /^apiVersion:/ { av = $2 }
    keep && /^kind:/       { kind = $2 }
    keep && /^  name:/     { if (av != "" && kind != "") { print av "\t" kind "\t" $2; av = ""; kind = "" } }
  '
)

# The extractor is the single point where this script can silently stop asserting
# anything: a broken pattern reports "no policy rendered" and exits 0, which is
# indistinguishable from a chart that legitimately renders none. Cross-check it
# against a count taken a different way, so a parsing bug fails loudly instead of
# turning into a green run. (This is not hypothetical — the first version of this
# awk had an unescaped `/` in a character class and did exactly that.)
source_lines="$(printf '%s\n' "$rendered" | grep -c '^# Source: .*/templates/kyverno-policies/' || true)"
if [ "$source_lines" -gt 0 ] && [ "${#policies[@]}" -eq 0 ]; then
  log_error "The render contains $source_lines kyverno-policies document(s) but none could be parsed."
  log_error "That is a bug in this script, not a clean cluster — refusing to report success."
  exit 2
fi

# "policy<TAB>rule<TAB>expected failureAction" for every rule of every policy
# this chart owns. What "the expected action" was rendered with is the render
# itself, not a second read of kyvernoPolicies.failureAction: this is the same
# reasoning check-loop-trap-shape.sh's header gives for asserting on real
# behaviour rather than re-deriving it — a second read can drift from what the
# template actually emitted, and drifting silently is exactly the failure mode
# this check exists to close (audit finding: the alias removal was
# indistinguishable from a working install where the value was already Audit).
mapfile -t expected_actions < <(
  printf '%s\n' "$rendered" | awk '
    /^# Source: .*\/templates\/kyverno-policies\// { keep = 1; next }
    /^# Source: /                                  { keep = 0; next }
    keep && /^  name:/                  { pname = $2 }
    keep && $1 == "-" && $2 == "name:"  { rname = $3 }
    keep && /^        failureAction:/   { print pname "\t" rname "\t" $2 }
  '
)

if [ "${#policies[@]}" -gt 0 ] && [ "${#expected_actions[@]}" -eq 0 ]; then
  log_error "${#policies[@]} polic(y|ies) rendered but no rule's failureAction could be parsed."
  log_error "That is a bug in this script, not a clean cluster — refusing to report success."
  exit 2
fi

if [ "${#policies[@]}" -eq 0 ]; then
  log_info "The chart renders no Kyverno policy — nothing to install, nothing to check."
  log_info "(kyverno.enabled or kyvernoPolicies.enabled is false in the values used.)"
  exit 0
fi

log_step "${#policies[@]} Kyverno policy manifest(s) rendered"

# ─── The cluster's CRDs ─────────────────────────────────────────────────────
# group<TAB>kind<TAB>plural<TAB>served,versions — resolved from the CRDs
# themselves rather than guessed, because the plural is what the second half
# needs to query and pluralising a Kind by hand is how you end up asserting
# nothing on a typo.
if ! crd_table="$("$KUBECTL" get crd -o jsonpath='{range .items[*]}{.spec.group}{"\t"}{.spec.names.kind}{"\t"}{.spec.names.plural}{"\t"}{range .spec.versions[?(@.served)]}{.name}{","}{end}{"\n"}{end}' 2>&1)"; then
  log_error "Cannot list CustomResourceDefinitions — is the cluster reachable?"
  printf '%s\n' "$crd_table" | sed 's/^/    /' | head -5
  exit 1
fi

errors=0
checked=0

# Distinct apiVersion/kind pairs — six policies share one CRD, so asserting per
# policy would report the same missing CRD six times.
while IFS=$'\t' read -r apiversion kind; do
  [ -n "$kind" ] || continue
  checked=$((checked + 1))

  group="${apiversion%/*}"
  version="${apiversion##*/}"

  row="$(printf '%s\n' "$crd_table" | awk -F'\t' -v g="$group" -v k="$kind" '$1 == g && $2 == k { print; exit }')"

  if [ -z "$row" ]; then
    log_error "  $apiversion $kind — no CRD for it in this cluster"
    log_error "      The Application will fail to sync with:"
    log_error "        no matches for kind \"$kind\" in version \"$apiversion\""
    log_error "      Install the Kyverno engine before enabling the policies"
    log_error "      (kyverno.enabled=true, kyvernoPolicies.enabled=false for the first pass)."
    errors=$((errors + 1))
    continue
  fi

  IFS=$'\t' read -r _g _k plural served <<<"$row"

  # Present is not sufficient: a CRD that no longer serves the version the chart
  # emits fails at exactly the same point, with a message that reads like the
  # CRD is missing entirely.
  if ! printf '%s' ",$served" | grep -q ",${version},"; then
    log_error "  $apiversion $kind — CRD exists but does not serve $version (served: ${served%,})"
    log_error "      A Kyverno major can retire an apiVersion; the chart must follow."
    errors=$((errors + 1))
    continue
  fi

  log_ok "  $apiversion $kind — CRD present and serving $version"

  [ "$CRDS_ONLY" -eq 1 ] && continue

  # ─── Second half: did the policies actually land? ─────────────────────────
  while IFS=$'\t' read -r av k name; do
    [ "$av" = "$apiversion" ] && [ "$k" = "$kind" ] || continue
    if ! "$KUBECTL" get "$plural.$group" "$name" >/dev/null 2>&1; then
      log_error "    $name — renders, is installable, and is NOT in the cluster"
      errors=$((errors + 1))
      continue
    fi
    log_ok "    $name"

    # ─── Third half: does the live object enforce what was rendered? ────────
    # Existing is not sufficient: a sync can leave a policy installed with a
    # STALE failureAction — ArgoCD out of sync, a manual `kubectl edit`, or the
    # 2026-08-20 alias removal this check was written for, where a silent
    # fallback to the chart default was precisely undetectable because the
    # value in play (Audit) already matched. Read from the live object, not
    # re-derived, for the same reason `expected_actions` reads the render.
    live_actions="$("$KUBECTL" get "$plural.$group" "$name" \
      -o jsonpath='{range .spec.rules[*]}{.name}{"="}{.validate.failureAction}{"\n"}{end}' 2>&1)"
    if [ -z "$live_actions" ]; then
      log_error "      could not read spec.rules[].validate.failureAction from the live object"
      errors=$((errors + 1))
      continue
    fi
    while IFS=$'\t' read -r ep er expected; do
      [ "$ep" = "$name" ] || continue
      live="$(printf '%s\n' "$live_actions" | awk -F= -v r="$er" '$1 == r { print $2; exit }')"
      if [ -z "$live" ]; then
        log_error "      rule '$er' — not found on the live object (rule renamed or removed?)"
        errors=$((errors + 1))
      elif [ "$live" != "$expected" ]; then
        log_error "      rule '$er' — cluster has failureAction=$live, chart renders $expected"
        log_error "          Application likely OutOfSync, or edited by hand — check ArgoCD."
        errors=$((errors + 1))
      fi
    done < <(printf '%s\n' "${expected_actions[@]}")
  done < <(printf '%s\n' "${policies[@]}")

done < <(printf '%s\n' "${policies[@]}" | cut -f1,2 | sort -u)

echo ""

if [ "$errors" -gt 0 ]; then
  log_error "$errors problem(s) between the rendered Kyverno policies and the cluster."
  if [ "$CRDS_ONLY" -eq 0 ]; then
    log_error "A policy that renders but is absent from the cluster is usually refused"
    log_error "upstream rather than broken: check the ArgoCD AppProject's"
    log_error "clusterResourceWhitelist, then the Application's sync conditions."
  fi
  exit 1
fi

if [ "$CRDS_ONLY" -eq 1 ]; then
  log_ok "All $checked Kyverno CRD(s) required by the render are present and serving."
else
  log_ok "All $checked Kyverno CRD(s) present, all ${#policies[@]} rendered policy(ies) exist in the"
  log_ok "cluster, and every rule enforces the failureAction the chart rendered."
fi
