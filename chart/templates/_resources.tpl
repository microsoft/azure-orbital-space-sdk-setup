{{- define "spacefx.resourceLimits" }}
{{- $serviceRes := .serviceValues.resources }}
{{- $globalRes := .globalValues.resources }}
resources:
  limits:
    cpu: {{ if and $serviceRes $serviceRes.cpu $serviceRes.cpu.limit }}{{ $serviceRes.cpu.limit }}{{ else }}{{ $globalRes.cpu.limit }}{{ end }}
    memory: {{ if and $serviceRes $serviceRes.memory $serviceRes.memory.limit }}{{ $serviceRes.memory.limit }}{{ else }}{{ $globalRes.memory.limit }}{{ end }}
  requests:
    cpu: {{ if and $serviceRes $serviceRes.cpu $serviceRes.cpu.request }}{{ $serviceRes.cpu.request }}{{ else }}{{ $globalRes.cpu.request }}{{ end }}
    memory: {{ if and $serviceRes $serviceRes.memory $serviceRes.memory.request }}{{ $serviceRes.memory.request }}{{ else }}{{ $globalRes.memory.request }}{{ end }}
{{- end }}