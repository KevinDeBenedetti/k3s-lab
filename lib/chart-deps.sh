# shellcheck shell=bash
# lib/chart-deps.sh — Read a chart's dependencies out of its Chart.yaml.
#
# Exists for the two umbrella checks:
#   scripts/check-umbrella-pins.sh    — are the pins the latest published?
#   scripts/check-umbrella-render.sh  — did every subchart actually contribute?
#
# platform-deployment pins its 7 subcharts by hand, and those pins are what a
# consumer resolves. The pins stay manual by choice — an alignment tool was
# written and then removed on 2026-07-30 as more surface than the gesture it
# replaced. What was missing was never the ability to *edit* the file, it was
# noticing that the edit had been forgotten, so this file only ever reads.
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
# Dependencies from classic HTTP repos are skipped: they are not addressable
# through the registry API that check-umbrella-pins.sh feeds.
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

# applicationset_chart_version APPLICATIONSET CHART — the version an ArgoCD
# ApplicationSet list generator pins for CHART, e.g. `platform-traefik`.
#
# Lives here rather than inside check-deployed-traefik.sh because it answers the
# same kind of question as the rest of this file — which version of a chart is
# a consumer actually going to resolve — just from a deployment manifest instead
# of a Chart.yaml. It is also the input to a security check, so it is worth unit
# tests of its own: reading the wrong element would report a clean version for a
# vulnerable deployment, which is worse than not checking at all.
#
# Matches on the element's `chart:` field, not its `name:`, because the two
# differ (`name: traefik` / `chart: platform-traefik`) and only `chart:` is what
# gets pulled from the registry.
applicationset_chart_version() {
  awk -v want="$2" '
    $1 == "-" && $2 == "name:"  { elem = 0 }
    $1 == "chart:"              { elem = ($2 == want) }
    elem && $1 == "version:"    { gsub(/"/, "", $2); print $2; exit }
  ' "$1"
}

# applicationset_charts APPLICATIONSET — every chart the list generator pins,
# as "chart<TAB>version" per line, in file order.
#
# The plural of applicationset_chart_version, for callers that must cover
# everything deployed rather than one named chart. Enumerating matters more
# than it looks: a check that only ever asks about charts it already knows the
# names of goes blind the day a component is added to the ApplicationSet — the
# new one is simply never checked, silently.
#
# Matches on `chart:`, not `name:`, because the two differ
# (`name: traefik` / `chart: platform-traefik`) and only `chart:` is what gets
# pulled from the registry. An element without a `version:` is skipped rather
# than emitted with an empty one, so callers never compare against "".
applicationset_charts() {
  awk '
    $1 == "-" && $2 == "name:" { chart = ""; next }
    $1 == "chart:"             { chart = $2; next }
    chart != "" && $1 == "version:" {
      gsub(/["'"'"']/, "", $2)
      if ($2 != "") print chart "\t" $2
      chart = ""
    }
  ' "$1"
}

# applicationset_chart_repo APPLICATIONSET — the registry the ApplicationSet
# actually pulls its charts from: the `repoURL` of the template source that
# carries a `chart:` field (the values source has none). Printed as written,
# minus quotes and an optional oci:// scheme — e.g. `ghcr.io/acme/charts`.
#
# Exists so that checks reading the ApplicationSet stop carrying their own
# copy of the registry path: the file that names the chart version is also the
# file that names where it resolves from, and a second copy of that truth
# drifts exactly like the version pins did.
applicationset_chart_repo() {
  awk '
    $1 == "-" && $2 == "repoURL:" { url = $3; next }
    $1 == "chart:" && url != ""   { gsub(/["'"'"']/, "", url)
                                    sub(/^oci:\/\//, "", url)
                                    print url; exit }
    $1 == "-"                     { url = "" }
  ' "$1"
}

# chart_oci_registry REPOSITORY NAME — the registry host and repository path a
# chart is published under, printed as "host<TAB>path". `oci://ghcr.io/acme/charts`
# plus `platform-traefik` gives `ghcr.io` and `acme/charts/platform-traefik`,
# which is what the OCI distribution API expects in /v2/<path>/tags/list.
chart_oci_registry() {
  local repo="${1#oci://}" name="$2"
  repo="${repo%/}"
  printf '%s\t%s/%s\n' "${repo%%/*}" "${repo#*/}" "$name"
}
