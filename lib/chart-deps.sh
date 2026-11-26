# shellcheck shell=bash
# lib/chart-deps.sh — Read a chart's dependencies out of its Chart.yaml.
#
# Exists for the two umbrella checks:
#   scripts/check-umbrella-pins.sh    — do the pins match the subcharts in the repo?
#   scripts/check-umbrella-render.sh  — did every subchart actually contribute?
# and, through chart_deps_build, for the checks that render a chart with its
# subcharts vendored (that one runs helm).
#
# platform-deployment pins its 7 subcharts, and those pins are what a consumer
# resolves. release-please bumps them together with the charts (one shared
# version), so this file only ever reads them.
#
# Source this file, then use:
#   chart_deps <Chart.yaml>       → one "name<TAB>version<TAB>repository" per line
#   chart_oci_deps <Chart.yaml>   → the same, restricted to oci:// repositories
#   chart_dep_names <Chart.yaml>  → just the names
#   chart_name <Chart.yaml>       → the chart's own name
#   chart_deps_isolate <name>     → point helm at a throwaway repository config,
#                                   removed on exit; call it once, before chart_deps_build
#   chart_deps_build <chart-dir>  → register its http(s) repositories, then
#                                   `helm dependency build` (the checks that render
#                                   a chart with its subcharts: check-resource-limits.sh,
#                                   check-rendered-images.sh, check-traefik-image.sh)

# chart_deps CHART_YAML — every declared dependency, as name/version/repository
# triples. Each field is printed without the quotes YAML allows around it
# (`repository: "https://…"` is the same URL to Helm), and the repository as an
# empty string when a dependency declares none.
chart_deps() {
  awk '
    function flush() {
      if (name != "") print name "\t" version "\t" repo
      name = ""; version = ""; repo = ""
    }
    # \047 is the single quote, which this single-quoted program cannot hold.
    function unquote(v) { gsub(/^["\047]|["\047]$/, "", v); return v }
    /^dependencies:/            { deps = 1; next }
    deps && /^[^[:space:]]/     { flush(); deps = 0 }
    deps && $1 == "-" && $2 == "name:" { flush(); name = unquote($3); next }
    deps && $1 == "version:"    { version = unquote($2); next }
    deps && $1 == "repository:" { repo = unquote($2); next }
    END                         { flush() }
  ' "$1"
}

# chart_oci_deps CHART_YAML — every dependency served from an `oci://` registry.
# Dependencies from classic HTTP repos are skipped: they are published
# elsewhere, so they are not this repository's pins.
chart_oci_deps() {
  chart_deps "$1" | awk -F'\t' '$3 ~ /^oci:\/\// { print }'
}

# chart_dep_names CHART_YAML — the name of every declared dependency, whatever
# the repository scheme. The render check needs all of them: a subchart pulled
# from a classic HTTP repo still has to produce manifests.
chart_dep_names() {
  chart_deps "$1" | cut -f1
}

# chart_name CHART_YAML — the chart's own name. `helm template` prefixes every
# `# Source:` path with it, so the render check needs it to attribute manifests.
chart_name() {
  awk '/^name:[[:space:]]*/ { print $2; exit }' "$1"
}

# chart_deps_isolate NAME — give helm a throwaway repository config and cache,
# so that chart_deps_build's `helm repo add` never reaches the caller's own
# `helm repo list`. Creates "$TMPDIR/NAME.XXXXXX", exports
# HELM_REPOSITORY_CONFIG / HELM_REPOSITORY_CACHE into it, sets CHART_DEPS_HOME
# to it, and removes it on exit.
#
# It owns the script's EXIT trap: a second `trap … EXIT` would replace this one
# and leave the directory behind, so a caller that needs more cleanup adds it
# to this trap rather than setting its own. Call it from the script's top level,
# never in a $(…) subshell: the exports and the trap would end with it.
#
# Explicit template: BSD mktemp (macOS) ignores TMPDIR for the bare `-d` form
# and goes through confstr instead, which GNU mktemp does not.
chart_deps_isolate() {
  CHART_DEPS_HOME="$(mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX")" || return
  # shellcheck disable=SC2064 # expanded now on purpose: the path is fixed
  trap "rm -rf '$CHART_DEPS_HOME'" EXIT
  export HELM_REPOSITORY_CONFIG="$CHART_DEPS_HOME/repositories.yaml"
  export HELM_REPOSITORY_CACHE="$CHART_DEPS_HOME/cache"
}

# chart_deps_build CHART_DIR — vendor the chart's dependencies at the versions
# its Chart.lock pins. `helm dependency build` resolves Chart.lock against
# *registered* repositories and fails with "no repository definition" on a
# fresh machine, so each http(s) repository is registered first (oci:// needs
# no registration). Run chart_deps_isolate first, to keep the caller's
# `helm repo list` untouched.
#
# A Chart.yaml that declares an http(s) repository while none was parsed (a
# flow-style `dependencies: [{…}]` list, which chart_deps cannot read) fails
# here, before helm runs. Registering nothing is how a parsing bug once
# surfaced three steps later as helm's "no repository definition": the first
# check-traefik-image.sh matched the URL with an awk regex that read nothing
# on the CI runner, and its job never passed.
# Returns 1 for that, otherwise helm's status; HELM (default: helm) is the test seam.
chart_deps_build() {
  local dir="$1" n=0 _name _version url
  while IFS=$'\t' read -r _name _version url; do
    case "$url" in
      http://*|https://*) ;;
      *) continue ;;
    esac
    n=$((n + 1))
    "${HELM:-helm}" repo add "$(basename "$dir")-dep${n}" "$url" --force-update >/dev/null || return
  done < <(chart_deps "$dir/Chart.yaml" | sort -u -t"$(printf '\t')" -k3,3)
  if [ "$n" -eq 0 ] && grep -qE '(^|[[:space:],{])repository:[[:space:]]*["'"'"']?https?://' "$dir/Chart.yaml"; then
    echo "chart_deps_build: $dir/Chart.yaml declares an http(s) repository, but none could be parsed, so none was registered" >&2
    return 1
  fi
  "${HELM:-helm}" dependency build "$dir" >/dev/null
}
