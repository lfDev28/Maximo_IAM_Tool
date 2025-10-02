{{/*
Expand the name of the chart.
*/}}
{{- define "keycloak-mas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "keycloak-mas.fullname" -}}
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
{{- define "keycloak-mas.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "keycloak-mas.labels" -}}
helm.sh/chart: {{ include "keycloak-mas.chart" . }}
{{ include "keycloak-mas.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "keycloak-mas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-mas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use for the Keycloak workload.
*/}}
{{- define "keycloak-mas.serviceAccountName" -}}
{{- $svc := .Values.keycloak.serviceAccount -}}
{{- if $svc.create }}
  {{- if $svc.name }}
    {{- tpl $svc.name . | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- include "keycloak-mas.keycloakFullname" . -}}
  {{- end -}}
{{- else -}}
  {{- if $svc.name -}}
    {{- tpl $svc.name . | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    default
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Dedicated fullname helper for the Keycloak control plane deployment.
*/}}
{{- define "keycloak-mas.keycloakFullname" -}}
{{- printf "%s-keycloak" (include "keycloak-mas.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the admin credential secret name with override support.
*/}}
{{- define "keycloak-mas.adminSecretName" -}}
{{- if .Values.keycloak.admin.existingSecret -}}
{{- tpl .Values.keycloak.admin.existingSecret . | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-admin" (include "keycloak-mas.keycloakFullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Build the fully qualified Keycloak container image reference.
*/}}
{{- define "keycloak-mas.keycloakImage" -}}
{{- $registry := trimSuffix "/" (default "" .Values.keycloak.image.registry) -}}
{{- $repository := trimPrefix "/" (default "rhbk/keycloak-rhel9" .Values.keycloak.image.repository) -}}
{{- $tag := default .Chart.AppVersion .Values.keycloak.image.tag -}}
{{- $digest := .Values.keycloak.image.digest -}}
{{- if $registry -}}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Extract the major Keycloak version from the image tag for feature toggles.
*/}}
{{- define "keycloak-mas.keycloakMajorVersion" -}}
{{- $tag := default .Chart.AppVersion .Values.keycloak.image.tag -}}
{{- $match := regexFind "^[0-9]+" $tag -}}
{{- if $match -}}
{{- $match -}}
{{- else -}}
26
{{- end -}}
{{- end -}}

{{/*
Resolve the PostgreSQL hostname Keycloak should target.
*/}}
{{- define "keycloak-mas.databaseHost" -}}
{{- if .Values.keycloak.database.host -}}
{{- tpl .Values.keycloak.database.host . -}}
{{- else -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the database secret that stores the Keycloak DB password.
*/}}
{{- define "keycloak-mas.databaseSecretName" -}}
{{- if .Values.keycloak.database.existingSecret -}}
{{- tpl .Values.keycloak.database.existingSecret . | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "keycloak-mas.postgresqlAuthSecretName" . -}}
{{- end -}}
{{- end -}}

{{/*
Determine the ConfigMap name containing the realm import payload.
*/}}
{{- define "keycloak-mas.realmConfigMapName" -}}
{{- if .Values.realm.import.configMapName -}}
{{- tpl .Values.realm.import.configMapName . | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-realm" (include "keycloak-mas.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Default name for the managed PostgreSQL auth secret.
*/}}
{{- define "keycloak-mas.postgresqlAuthSecretName" -}}
{{- if .Values.postgresqlAuth.secretName -}}
{{- .Values.postgresqlAuth.secretName | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-pg-auth" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}
