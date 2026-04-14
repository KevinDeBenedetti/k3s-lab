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
