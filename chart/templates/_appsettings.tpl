{{- define "spacefx.appsettings.json" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $serviceLogging := $globalValues.logging }}
{{- if $serviceValues.logging }}
{{- $serviceLogging := $serviceValues.logging }}
{{- end }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $serviceValues.appName }}-config
  namespace: {{ $serviceValues.serviceNamespace }}
  labels:
    app: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/app-name: {{ default "" $serviceValues.appName | quote }}
    microsoft.azureorbital/serviceName: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/isDebugShim: {{ $serviceValues.debugShim | quote }}
    microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
    type: "ConfigMap"
data:
  appsettings.json: |-
    {
      "Logging": {
          "LogLevel": {
            {{- if $serviceValues.debugShim }}
              {{- range $index, $logging := $globalValues.debugShim.logging }}
                {{ $logging.name | quote }}: {{ $logging.level | quote }}
                {{- if ne $index (sub (len $serviceLogging) 1) }},{{ end }}
              {{- end }}
            {{- else }}
              {{- range $index, $logging := $serviceLogging }}
                {{ $logging.name | quote }}: {{ $logging.level | quote }}
                {{- if ne $index (sub (len $serviceLogging) 1) }},{{ end }}
              {{- end }}
            {{- end }}
          },
          "Console": {
            "TimestampFormat": "[yyyy-MM-dd HH:mm:ss] ",
            "DisableColors": true
          }
      },
      "AllowedHosts": "*",
      "Kestrel": {
          "EndpointDefaults": {
              "Protocols": "Http2"
          }
      }
    }
{{ end }}



{{- define "spacefx.appsettings.json.volume" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
name: {{ $serviceValues.appName }}-config-volume
configMap:
  name: {{ $serviceValues.appName }}-config
{{- end }}

{{- define "spacefx.appsettings.json.volumemount" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
name: {{ $serviceValues.appName }}-config-volume
mountPath: {{ $globalValues.spacefxSecretDirectory }}
{{- end }}