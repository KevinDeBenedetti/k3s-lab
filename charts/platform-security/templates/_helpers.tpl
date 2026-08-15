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

Precedence, highest first:
  1. `kyvernoPolicies.failureAction`           — canonical, matches the CRD field
  2. `kyvernoPolicies.validationFailureAction` — deprecated alias, still honoured
  3. `Audit`                                   — the chart default

The alias exists because infra pins this chart and sets the old key
(infra/platform/security/values.yaml). Helm silently ignores unknown value keys,
so dropping it outright would not error — it would quietly fall back to the chart
default, which is precisely the kind of silent action change this chart's tests
exist to prevent. Remove the alias only once infra sets `failureAction`.

The default lives here and NOT in values.yaml on purpose: a `failureAction: Audit`
in values.yaml is indistinguishable from an operator setting it, so it would win
over the alias in step 2 and make the alias dead code — which is exactly what the
first version of this helper did.

`fail` on an unrecognised value: a bogus action is accepted by the API server and
silently defaults, so a typo must break the render, not the cluster.
*/}}
{{- define "platform-security.failureAction" -}}
{{- $p := .Values.kyvernoPolicies -}}
{{- $action := $p.failureAction | default $p.validationFailureAction | default "Audit" -}}
{{- if not (has $action (list "Audit" "Enforce")) -}}
{{- fail (printf "kyvernoPolicies.failureAction must be Audit or Enforce, got %q" ($action | toString)) -}}
{{- end -}}
{{- $action -}}
{{- end }}
