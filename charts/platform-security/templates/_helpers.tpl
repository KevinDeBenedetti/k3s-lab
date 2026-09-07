{{/*
Expand the name of the chart.
*/}}
{{- define "platform-security.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "platform-security.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform-security.labels" -}}
helm.sh/chart: {{ include "platform-security.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Resolve the Kyverno validation failure action for a rule.

Kyverno 3.8 deprecates `spec.validationFailureAction` in favour of the per-rule
`spec.rules[].validate.failureAction` — the CRD shipped by the pinned kyverno
3.8.1 subchart describes the old field as "Deprecated, use validationFailureAction
under the validate rule instead". Both still work today; the old one will not
survive a Kyverno major.

The action comes from `kyvernoPolicies.failureAction`, which matches the CRD
field, and falls back to `Audit`, the chart default.

`kyvernoPolicies.validationFailureAction` was a deprecated alias for it from
2026-08-14 to 2026-08-20. It existed for a single consumer — infra pinned this
chart and set the old key — and this helper said the alias could go once infra
set `failureAction`, which it did on 2026-08-19.

The alias is now *rejected*, not merely gone. Helm ignores an unknown value key
in silence, so an install still passing the old key would not error: it would
quietly drop to the chart default, turning an `Enforce` install into an `Audit`
one with nothing to read in the diff. `fail` is what makes that impossible —
the same reasoning as the bogus-value check below, applied to a stale key
instead of a stale value.

The default lives here and NOT in values.yaml: `failureAction: null` there keeps
values.yaml from asserting an action it does not own, and routes every install
through the validation below — a literal `Audit` in values.yaml would be a
second, unvalidated source for the same decision.

`fail` on an unrecognised value: a bogus action is accepted by the API server and
silently defaults, so a typo must break the render, not the cluster.
*/}}
{{- define "platform-security.failureAction" -}}
{{- $p := .Values.kyvernoPolicies -}}
{{- if $p.validationFailureAction -}}
{{- fail (printf "kyvernoPolicies.validationFailureAction was removed on 2026-08-20; rename it to kyvernoPolicies.failureAction (got %q)" ($p.validationFailureAction | toString)) -}}
{{- end -}}
{{- $action := $p.failureAction | default "Audit" -}}
{{- if not (has $action (list "Audit" "Enforce")) -}}
{{- fail (printf "kyvernoPolicies.failureAction must be Audit or Enforce, got %q" ($action | toString)) -}}
{{- end -}}
{{- $action -}}
{{- end }}
