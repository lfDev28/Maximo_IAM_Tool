{{/*
Preconfigure PostgreSQL authentication defaults before templates render.
*/}}
{{- define "keycloak-mas.configurePostgresqlAuth" -}}
{{- if not .Values.global -}}
  {{- $_ := set .Values "global" (dict) -}}
{{- end -}}
{{- if not (index .Values.global "postgresql") -}}
  {{- $_ := set .Values.global "postgresql" (dict "auth" (dict)) -}}
{{- else if not (index .Values.global.postgresql "auth") -}}
  {{- $_ := set .Values.global.postgresql "auth" (dict) -}}
{{- end -}}
{{- if not (index .Values "postgresql") -}}
  {{- $_ := set .Values "postgresql" (dict "auth" (dict)) -}}
{{- else if not (index .Values.postgresql "auth") -}}
  {{- $_ := set .Values.postgresql "auth" (dict) -}}
{{- end -}}

{{- $secretName := include "keycloak-mas.postgresqlAuthSecretName" . -}}
{{- $_ := set .Values.postgresqlAuth "secretName" $secretName -}}

{{- $userSecret := "" -}}
{{- if .Values.keycloak.database.existingSecret -}}
  {{- $userSecret = tpl .Values.keycloak.database.existingSecret . -}}
{{- else if .Values.postgresql.auth.existingSecret -}}
  {{- $userSecret = tpl .Values.postgresql.auth.existingSecret . -}}
{{- else if .Values.global.postgresql.auth.existingSecret -}}
  {{- $userSecret = tpl .Values.global.postgresql.auth.existingSecret . -}}
{{- end -}}

{{- $manage := and .Values.postgresqlAuth.create (or (eq $userSecret "") (eq $userSecret $secretName)) -}}
{{- if not $manage -}}
  {{- $_ := set .Values.postgresqlAuth "managed" false -}}
{{- end -}}
{{- if $manage -}}
  {{- $namespace := default .Release.Namespace .Values.namespaceOverride -}}
  {{- if not $namespace -}}
    {{- $namespace = "default" -}}
  {{- end -}}
  {{- $existing := lookup "v1" "Secret" $namespace $secretName -}}
  {{- $existingData := dict -}}
  {{- if and $existing $existing.data -}}
    {{- $existingData = $existing.data -}}
  {{- end -}}
  {{- $existingPassword := "" -}}
  {{- $existingPostgresPassword := "" -}}
  {{- if $existingData -}}
    {{- if hasKey $existingData "password" -}}
      {{- $existingPassword = (index $existingData "password") | b64dec -}}
    {{- end -}}
    {{- if hasKey $existingData "postgres-password" -}}
      {{- $existingPostgresPassword = (index $existingData "postgres-password") | b64dec -}}
    {{- end -}}
  {{- end -}}
  {{- $resolvedPassword := default $existingPassword .Values.postgresqlAuth.password -}}
  {{- if not $resolvedPassword -}}
    {{- $resolvedPassword = randAlphaNum 24 -}}
  {{- end -}}
  {{- $resolvedPostgresPassword := default $existingPostgresPassword .Values.postgresqlAuth.postgresPassword -}}
  {{- if not $resolvedPostgresPassword -}}
    {{- $resolvedPostgresPassword = $resolvedPassword -}}
  {{- end -}}
  {{- $_ := set .Values.postgresqlAuth "resolvedPassword" $resolvedPassword -}}
  {{- $_ := set .Values.postgresqlAuth "resolvedPostgresPassword" $resolvedPostgresPassword -}}
  {{- $_ := set .Values.postgresqlAuth "managed" true -}}
  {{- $_ := set .Values.postgresql.auth "existingSecret" $secretName -}}
  {{- $_ := set .Values.postgresql.auth "password" $resolvedPassword -}}
  {{- $_ := set .Values.postgresql.auth "postgresPassword" $resolvedPostgresPassword -}}
  {{- $_ := set .Values.global.postgresql.auth "existingSecret" $secretName -}}
  {{- $_ := set .Values.global.postgresql.auth "password" $resolvedPassword -}}
  {{- $_ := set .Values.global.postgresql.auth "postgresPassword" $resolvedPostgresPassword -}}
{{- end -}}

{{- if not .Values.postgresql.auth.username -}}
  {{- $_ := set .Values.postgresql.auth "username" .Values.keycloak.database.username -}}
{{- end -}}
{{- if not .Values.global.postgresql.auth.username -}}
  {{- $_ := set .Values.global.postgresql.auth "username" .Values.keycloak.database.username -}}
{{- end -}}

{{- if and $manage (not .Values.global.postgresql.auth.database) -}}
  {{- $_ := set .Values.global.postgresql.auth "database" .Values.keycloak.database.name -}}
{{- end -}}

{{- if or $manage (eq $userSecret $secretName) -}}
  {{- if not .Values.keycloak.database.existingSecret -}}
    {{- $_ := set .Values.keycloak.database "existingSecret" $secretName -}}
  {{- end -}}
{{- else -}}
  {{- if $userSecret -}}
    {{- if not .Values.keycloak.database.existingSecret -}}
      {{- $_ := set .Values.keycloak.database "existingSecret" $userSecret -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
