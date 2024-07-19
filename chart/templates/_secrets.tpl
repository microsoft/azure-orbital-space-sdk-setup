{{- define "spacefx.secrets" }}
{{- $buildServiceValues := .buildServiceValues }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $payloadAppValues := .payloadAppValues }}
{{- $fileServerValues := .fileServerValues }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $serviceValues.appName }}-secret
  namespace: {{ $serviceValues.serviceNamespace }}
  labels:
    app: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/isDebugShim: {{ $serviceValues.debugShim | quote }}
    type: "Secret"
data:
  spacefx_version: {{ $globalValues.spacefxVersion | b64enc }}
  spacefx_cache: {{ $globalValues.spacefxDirectories.base | b64enc }}
  spacefx_dir_plugins: {{ printf "%s/%s/%s" $globalValues.spacefxDirectories.base $globalValues.spacefxDirectories.plugins $serviceValues.appName | b64enc }}
  spacefx_dir_xfer: {{ printf "%s/%s/%s" $globalValues.spacefxDirectories.base $globalValues.spacefxDirectories.xfer $serviceValues.appName | b64enc }}
  heartbeatpulsetimingms: {{ printf "%.0f" $globalValues.appConfig.heartBeatPulseTimingMS | b64enc }}
  heartbeatreceivedtolerancems: {{ printf "%.0f" $globalValues.appConfig.heartBeatReceivedToleranceMS | b64enc }}
  resourcemonitorenabled: {{ $globalValues.appConfig.resourceMonitorEnabled | ternary "true" "false" | b64enc }}
  resourcemonitortimingms: {{ printf "%.0f" $globalValues.appConfig.resourceMonitorTimingMS | b64enc }}
  resourcescavengerenabled: {{ $globalValues.appConfig.resourceScavengerEnabled | ternary "true" "false" | b64enc }}
  resourcescavengertimingms: {{ printf "%.0f" $globalValues.appConfig.resourceScavengerTimingMS | b64enc }}
  {{- range $key, $configItem := $serviceValues.appConfig }}
  {{ $configItem.name | lower }}: {{ $configItem.value | toString | b64enc }}
  {{- end }}
  {{- if eq $serviceValues.appName "platform-deployment" }}
  {{- $templatePayloadAppValues := $payloadAppValues }}
  {{- $_ := set $templatePayloadAppValues "appName" "SPACEFX-TEMPLATE_APP_NAME" }}
  {{- $_ := set $templatePayloadAppValues "serviceNamespace" "SPACEFX-TEMPLATE_APP_NAMESPACE" }}
  {{- $payloadappconfig := include "spacefx.secrets" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues "fileServerValues" $fileServerValues "payloadAppValues" .payloadAppValues) | trim }}
  {{- $daprannotationsOutput := include "spacefx.daprannotations" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues) | trim }}
  {{- $fileServerClientPVC := include "spacefx.fileserver.persistentvolumeclaim" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues "fileServerValues" $fileServerValues) | trim }}
  {{- $fileServerClientPV := include "spacefx.fileserver.persistentvolume" (dict "serviceValues" $templatePayloadAppValues "globalValues" $globalValues "fileServerValues" $fileServerValues) | trim }}
  {{- $fileServerClientVolumeMounts := include "spacefx.secrets.volumemount" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues) | trim }}
  {{- $fileServerClientVolumes := include "spacefx.secrets.volume" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues) | trim  }}
  {{- range $volumeKey, $volumeName := $globalValues.xferVolumes }}
  {{- $fileServerClientVolumeMount := include "spacefx.fileserver.clientapp.volumemount" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues "volumeName" $volumeName) | trim }}
  {{- $fileServerClientVolumeMounts = printf "%s\n%s" $fileServerClientVolumeMounts $fileServerClientVolumeMount }}
  {{- end }}
  {{- if $templatePayloadAppValues.xferVolumes }}
  {{- range $volumeKey, $volumeName := $templatePayloadAppValues.xferVolumes }}
  {{- $fileServerClientVolumeMount := include "spacefx.fileserver.clientapp.volumemount" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues "volumeName" $volumeName) | trim }}
  {{- $fileServerClientVolumeMounts = printf "%s\n%s" $fileServerClientVolumeMounts $fileServerClientVolumeMount }}
  {{- end }}
  {{- end }}
  {{- if hasPrefix "\n" $fileServerClientVolumeMounts }}
  {{- $fileServerClientVolumeMounts = trimPrefix "\n" $fileServerClientVolumeMounts }}
  {{- end }}
  {{- range $volumeKey, $volumeName := $globalValues.xferVolumes }}
  {{- $fileServerClientVolume := include "spacefx.fileserver.clientapp.volume" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues "volumeName" $volumeName) | trim }}
  {{- $fileServerClientVolumes = printf "%s\n%s" $fileServerClientVolumes $fileServerClientVolume }}
  {{- end }}
  {{- if $templatePayloadAppValues.xferVolumes }}
  {{- range $volumeKey, $volumeName := $templatePayloadAppValues.xferVolumes }}
  {{- $fileServerClientVolume := include "spacefx.fileserver.clientapp.volume" (dict "globalValues" $globalValues "serviceValues" $templatePayloadAppValues "volumeName" $volumeName) | trim }}
  {{- $fileServerClientVolumes = printf "%s\n%s" $fileServerClientVolumes $fileServerClientVolume }}
  {{- end }}
  {{- end }}
  {{- if hasPrefix "\n" $fileServerClientVolumes }}
  {{- $fileServerClientVolumes = trimPrefix "\n" $fileServerClientVolumes }}
  {{- end }}
  buildservicerepository: {{ $buildServiceValues.repository | b64enc }}
  buildservicetag: {{ $buildServiceValues.tag | b64enc }}
  containerregistry: {{ $globalValues.containerRegistry | b64enc }}
  containerregistryinternal: {{ $globalValues.containerRegistryInternal | b64enc }}
  daprannotations: {{ $daprannotationsOutput | b64enc }}
  fileserverappcredname: {{ printf "fileserver-%s" $templatePayloadAppValues.appName | b64enc }}
  fileservercredname: {{ printf "%s-fileserver-config" $fileServerValues.serviceNamespace | b64enc }}
  fileservercrednamespace: {{ $fileServerValues.serviceNamespace | b64enc }}
  fileserverclientpv: {{ $fileServerClientPV | b64enc }}
  fileserverclientpvc: {{ $fileServerClientPVC | b64enc }}
  fileServerclientvolumemounts: {{ $fileServerClientVolumeMounts | b64enc }}
  fileServerclientvolumes: {{ $fileServerClientVolumes | b64enc }}
  payloadappannotations: {{ toYaml $serviceValues.payloadAppInjections.annotations | b64enc }}
  payloadappconfig: {{ $payloadappconfig | b64enc }}
  payloadapplabels: {{ toYaml $serviceValues.payloadAppInjections.labels | b64enc }}
  payloadappenvironmentvariables: {{ toYaml $serviceValues.payloadAppInjections.environmentVariables | b64enc }}
  fileserversmb: {{ $globalValues.fileserverSMB | ternary "true" "false" | b64enc }}
  {{- end }}
{{- end }}

{{- define "spacefx.secrets.volume" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
name: {{ $serviceValues.appName }}-secret-volume
secret:
  secretName: {{ $serviceValues.appName }}-secret
{{- end }}

{{- define "spacefx.secrets.volumemount" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
name: {{ $serviceValues.appName }}-secret-volume
mountPath: {{ $globalValues.spacefxSecretDirectory | quote }}
{{- end }}