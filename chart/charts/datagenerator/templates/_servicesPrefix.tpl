{{- define "spacefx.dataGenerator.servicePrefixCalc" -}}
{{- $globalValues := .globalValues }}
{{- $containerRegistry := .containerRegistry | default $globalValues.containerRegistry }}
{{- if $globalValues.servicesPrefix -}}
{{- printf "%s/%s" $containerRegistry $globalValues.servicesPrefix -}}
{{- else -}}
{{- printf "%s" $containerRegistry -}}
{{- end -}}
{{- end -}}