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
2026-08-14 to 2026-08-20 — a single consumer (infra) pinned this chart and set
the old key, until it moved to `failureAction` on 2026-08-19. For the day after
that, a dedicated `fail` lived here rejecting the stale key by name: Helm
otherwise ignores an unknown value key in silence, which would have quietly
dropped an `Enforce` install back to `Audit` with nothing to read in the diff.

That dedicated `fail` is gone as of 2026-09-07: `values.schema.json` now sets
`additionalProperties: false` on the whole `kyvernoPolicies` object, so ANY
unrecognised key — `validationFailureAction` included, or a typo like
`faliureAction` the alias-specific check never covered — fails the render
before this template even runs. Schema validation happens first, so the old
`fail` had become unreachable dead code the moment the schema landed; kept
this comment's history rather than the branch itself.

The default lives here and NOT in values.yaml: `failureAction: null` there keeps
values.yaml from asserting an action it does not own, and routes every install
through the validation below — a literal `Audit` in values.yaml would be a
second, unvalidated source for the same decision.

`fail` on an unrecognised value: a bogus action is accepted by the API server and
silently defaults, so a typo must break the render, not the cluster.
*/}}
{{- define "platform-security.failureAction" -}}
{{- $p := .Values.kyvernoPolicies -}}
{{- $action := $p.failureAction | default "Audit" -}}
{{- if not (has $action (list "Audit" "Enforce")) -}}
{{- fail (printf "kyvernoPolicies.failureAction must be Audit or Enforce, got %q" ($action | toString)) -}}
{{- end -}}
{{- $action -}}
{{- end }}
