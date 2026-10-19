# shellcheck shell=bash
# lib/chart-deps.sh — Read a chart's dependencies out of its Chart.yaml.
#
# Exists for the two umbrella checks:
#   scripts/check-umbrella-pins.sh    — do the pins match the subcharts in the repo?
#   scripts/check-umbrella-render.sh  — did every subchart actually contribute?
#
# platform-deployment pins its 7 subcharts, and those pins are what a consumer
# resolves. release-please bumps them together with the charts (one shared
# version), so this file only ever reads.
#
# Source this file, then use:
#   chart_deps <Chart.yaml>       → one "name<TAB>version<TAB>repository" per line
#   chart_oci_deps <Chart.yaml>   → the same, restricted to oci:// repositories
#   chart_dep_names <Chart.yaml>  → just the names
#   chart_name <Chart.yaml>       → the chart's own name

# chart_deps CHART_YAML — every declared dependency, as name/version/repository
# triples. The repository field is printed as written, including an empty string
# when a dependency declares none.
chart_deps() {
  awk '
    function flush() {
      if (name != "") print name "\t" version "\t" repo
      name = ""; version = ""; repo = ""
    }
    /^dependencies:/            { deps = 1; next }
    deps && /^[^[:space:]]/     { flush(); deps = 0 }
    deps && $1 == "-" && $2 == "name:" { flush(); name = $3; next }
    deps && $1 == "version:"    { version = $2; next }
    deps && $1 == "repository:" { repo = $2; next }
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
