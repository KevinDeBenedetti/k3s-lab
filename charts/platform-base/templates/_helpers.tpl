{{/*
Expand the name of the chart.
*/}}
{{- define "platform-base.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "platform-base.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform-base.labels" -}}
helm.sh/chart: {{ include "platform-base.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
