{{/*
Expand the name of the chart.
*/}}
{{- define "platform-monitoring.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "platform-monitoring.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform-monitoring.labels" -}}
helm.sh/chart: {{ include "platform-monitoring.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
