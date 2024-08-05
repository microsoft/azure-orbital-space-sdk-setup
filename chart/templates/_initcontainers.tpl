{{- define "spacefx.initcontainers.setperms" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $mountPaths := "" }}
initContainers:
  - name: init-permissions
    image: docker.io/rancher/mirrored-library-busybox:1.36.1
    volumeMounts:
{{- range $volumeKey, $volumeName := $globalValues.xferVolumes }}
{{- $fileServerVolumeMount := printf "%s" (include "spacefx.fileserver.clientapp.volumemount" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | nindent 2 | trim) }}
{{- $fileServerVolumeMountPath := printf "%s" (include "spacefx.fileserver.clientapp.volumemount.mountpath" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | trim) }}
{{- $mountPaths = printf "%s %s" $mountPaths $fileServerVolumeMountPath }}
{{- printf "- %s" $fileServerVolumeMount | nindent 5 }}
{{- end }}
{{- if $serviceValues.xferVolumes }}
{{- range $volumeKey, $volumeName := $serviceValues.xferVolumes }}
{{- $fileServerVolumeMount := printf "%s" (include "spacefx.fileserver.clientapp.volumemount" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | nindent 2 | trim) }}
{{- $fileServerVolumeMountPath := printf "%s" (include "spacefx.fileserver.clientapp.volumemount.mountpath" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | trim) }}
{{- $mountPaths = printf "%s %s" $mountPaths $fileServerVolumeMountPath }}
{{- printf "- %s" $fileServerVolumeMount | nindent 5 }}
{{- end }}
{{- end }}
    command: ["sh", "-c", "chown -R {{ $serviceValues.runAsUserId }}:{{ $serviceValues.runAsUserId }} {{ $mountPaths }}"]
{{- end }}

