{{- define "spacefx.payloadappTemplate.annotations" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- if $serviceValues.annotations.daprEnabled }}
{{- include "spacefx.daprannotations" (dict "globalValues" $globalValues "serviceValues" $serviceValues) }}
{{- end }}
azure.spacefx/app-schedule: {{ $serviceValues.schedule | quote }}
azure.spacefx/max-duration: {{ $serviceValues.maxduration | quote }}
azure.spacefx/start-time: {{ $serviceValues.starttime | quote }}
{{- end }}