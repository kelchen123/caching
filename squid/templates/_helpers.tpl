{{/*
Expand the name of the chart.
*/}}
{{- define "squid.name" -}}
squid
{{- end }}

{{/*fully qualified app name.*/}}
{{- define "squid.fullname" -}}
squid
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "squid.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "squid.labels" -}}
helm.sh/chart: {{ include "squid.chart" . }}
{{ include "squid.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "squid.selectorLabels" -}}
app.kubernetes.io/name: {{ include "squid.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: squid-proxy
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "squid.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "squid.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
