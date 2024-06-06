{{- define "spacefx.resourceLimits" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
resources:
  limits:
{{- if and $serviceValues (not (empty $serviceValues.resources)) (not (empty $serviceValues.resources.cpu)) (not (empty $serviceValues.resources.cpu.limit)) }}
    cpu: {{ $serviceValues.resources.cpu.limit }}
{{- else }}
    cpu: {{ $globalValues.resources.cpu.limit }}
{{- end }}
{{- if and $serviceValues (not (empty $serviceValues.resources)) (not (empty $serviceValues.resources.memory)) (not (empty $serviceValues.resources.memory.limit)) }}
    memory: {{ $serviceValues.resources.memory.limit }}
{{- else }}
    memory: {{ $globalValues.resources.memory.limit }}
{{- end }}
  requests:
{{- if and $serviceValues (not (empty $serviceValues.resources)) (not (empty $serviceValues.resources.cpu)) (not (empty $serviceValues.resources.cpu.request)) }}
    cpu: {{ $serviceValues.resources.cpu.request }}
{{- else }}
    cpu: {{ $globalValues.resources.cpu.request }}
{{- end }}
{{- if and $serviceValues (not (empty $serviceValues.resources)) (not (empty $serviceValues.resources.memory)) (not (empty $serviceValues.resources.memory.request)) }}
    memory: {{ $serviceValues.resources.memory.request }}
{{- else }}
    memory: {{ $globalValues.resources.memory.request }}
{{- end }}
{{- end }}