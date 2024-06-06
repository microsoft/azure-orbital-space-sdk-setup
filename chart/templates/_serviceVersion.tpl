{{- define "spacefx.serviceVersionCalc" -}}
{{- $globalValues := .globalValues }}
{{- $serviceValues := .serviceValues }}
{{- if $serviceValues.tag -}}
{{- printf "%s" $serviceValues.tag -}}
{{- else -}}
{{- printf "%s" $globalValues.spacefxVersion -}}
{{- end -}}
{{- end -}}