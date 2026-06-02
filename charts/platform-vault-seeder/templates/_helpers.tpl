{{/*
Expand the name of the chart.
*/}}
{{- define "platform-vault-seeder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "platform-vault-seeder.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "platform-vault-seeder.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform-vault-seeder.labels" -}}
helm.sh/chart: {{ include "platform-vault-seeder.chart" . }}
{{ include "platform-vault-seeder.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "platform-vault-seeder.selectorLabels" -}}
app.kubernetes.io/name: {{ include "platform-vault-seeder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Vault CLI helper — returns command to execute vault CLI via kubectl exec
Usage: {{ include "platform-vault-seeder.vaultExec" . }}
*/}}
{{- define "platform-vault-seeder.vaultExec" -}}
kubectl --context {{ .Values.global.kubeContext }} exec -n {{ .Values.global.vaultNamespace }} {{ .Values.global.vaultPod }} -- env VAULT_TOKEN="${VAULT_ROOT_TOKEN}" VAULT_SKIP_VERIFY=true vault
{{- end }}

{{/*
Vault CLI helper for stdin input (policies, etc.)
Usage: {{ include "platform-vault-seeder.vaultExecStdin" . }}
*/}}
{{- define "platform-vault-seeder.vaultExecStdin" -}}
kubectl --context {{ .Values.global.kubeContext }} exec -i -n {{ .Values.global.vaultNamespace }} {{ .Values.global.vaultPod }} -- env VAULT_TOKEN="${VAULT_ROOT_TOKEN}" VAULT_SKIP_VERIFY=true vault
{{- end }}
