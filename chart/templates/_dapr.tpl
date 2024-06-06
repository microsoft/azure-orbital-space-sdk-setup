{{- define "spacefx.daprannotations" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
dapr.io/enabled: "true"
dapr.io/app-id: {{ $serviceValues.appName | quote }}
dapr.io/app-protocol:   "grpc"
dapr.io/app-port: "50051"
dapr.io/log-level: {{ $globalValues.dapr.logLevel | quote }}
dapr.io/enable-api-logging: "true"
{{- if $serviceValues.debugShim }}
dapr.io/sidecar-liveness-probe-delay-seconds: "2"
dapr.io/sidecar-liveness-probe-period-seconds: "2"
dapr.io/sidecar-liveness-probe-threshold: "9999"
{{- end }}
{{- end }}