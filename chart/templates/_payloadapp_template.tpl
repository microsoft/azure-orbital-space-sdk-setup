{{- define "spacefx.payloadappTemplate.annotations" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- if $serviceValues.annotations.daprEnabled }}
{{- include "spacefx.daprannotations" (dict "globalValues" $globalValues "serviceValues" $serviceValues) }}
{{- end }}
microsoft.azureorbital/app-name: {{ default "" $serviceValues.appName | quote }}
app: {{ default "" $serviceValues.appName | quote }}
microsoft.azureorbital/max-duration: {{ default "" $serviceValues.schedule.maxDuration | quote }}
microsoft.azureorbital/start-time: {{ default "" $serviceValues.schedule.startTime | quote }}
microsoft.azureorbital/end-time: {{ default "" $serviceValues.schedule.endTime | quote }}
microsoft.azureorbital/recurring: {{ default "" $serviceValues.schedule.recurringSchedule | quote }}
{{- end }}

{{- define "spacefx.payloadappTemplate.labels" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
microsoft.azureorbital/app-name: {{ default "" $serviceValues.appName | quote }}
app: {{ default "" $serviceValues.appName | quote }}
microsoft.azureorbital/app-group: {{ default "" $serviceValues.appGroup | quote }}
microsoft.azureorbital/app-namespace: {{ default "" $serviceValues.serviceNamespace | quote }}
microsoft.azureorbital/tracking-id: {{ default "" $serviceValues.trackingId | quote }}
microsoft.azureorbital/customer-tracking-id: {{ default "" $serviceValues.customerTrackingId | quote }}
microsoft.azureorbital/correlation-id: {{ default "" $serviceValues.correlationId | quote }}
{{- end }}

{{- define "spacefx.payloadappTemplate.environmentVariables" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $platformDeployment := .platformDeployment }}
SPACEFX_APP: {{ default "" $serviceValues.appName | quote }}
SPACEFX_APP_GROUP: {{ default "" $serviceValues.appGroup | quote }}
SPACEFX_SCHEDULE_RECURRING: {{ default "" $serviceValues.schedule.recurringSchedule | quote }}
SPACEFX_SCHEDULE_MAXDURATION: {{ default "" $serviceValues.schedule.maxDuration | quote }}
SPACEFX_SCHEDULE_STARTTIME: {{ default "" $serviceValues.schedule.startTime | quote }}
SPACEFX_SCHEDULE_ENDTIME: {{ default "" $serviceValues.schedule.endTime | quote }}
SPACEFX_APP_NAMESPACE: {{ default "" $serviceValues.serviceNamespace | quote }}
SPACEFX_TRACKING_ID: {{ default "" $serviceValues.trackingId | quote }}
SPACEFX_CUSTOMER_TRACKING_ID: {{ default "" $serviceValues.customerTrackingId | quote }}
SPACEFX_CORRELATION_ID: {{ default "" $serviceValues.correlationId | quote }}
SPACEFX_DIR: {{ default "" $globalValues.spacefxDirectories.base | quote }}
SPACEFX_SECRET_DIR: {{ default "" $globalValues.spacefxSecretDirectory | quote }}
APP_CONTEXT: {{ default "" $serviceValues.appContext | quote  }}
{{- range $index, $envvar := $platformDeployment.payloadAppInjections.environmentVariables }}
{{ $envvar.name }}: {{ default "" $envvar.value | quote }}
{{- end }}
{{- end }}