{{- define "spacefx.fileserver.clientapp.creds" }}
{{- $password := .password }}
{{- $username := .username }}
{{- $serviceValues := .serviceValues }}
---
apiVersion: v1
kind: Secret
metadata:
  name: fileserver-{{ $username }}
  namespace: {{ $serviceValues.serviceNamespace | quote }}
  labels:
    microsoft.azureorbital/serviceName: {{ $serviceValues.appName | quote }}
type: Opaque
data:
  username: {{ $username | b64enc }}
  password: {{ $password | b64enc }}
{{- end }}


{{- define "spacefx.fileserver.persistentvolume" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $fileServerValues := .fileServerValues }}
{{- $volumesList := $globalValues.xferVolumes }}
{{- if $serviceValues.xferVolumes }}
{{- range $serviceVolumeKey, $serviceVolumeName := $serviceValues.xferVolumes }}
{{- $volumesList = append $volumesList $serviceVolumeName }}
{{- end }}
{{- end }}
{{- $first := true }}
{{- range $volumeKey, $volumeDirName := $volumesList }}
{{- $volumeName := printf "%s-%s" $serviceValues.appName $volumeDirName }}
{{- $volumeNameFQDN := printf "%s.%s.svc.cluster.local/%s" $fileServerValues.appName $fileServerValues.serviceNamespace $volumeName }}
{{- if not $first }}
---
{{- else }}
{{- $first = false }}
{{- end }}
apiVersion: v1
kind: PersistentVolume
metadata:
{{- if eq $globalValues.fileserverSMB true }}
  annotations:
    pv.kubernetes.io/provisioned-by: smb.csi.k8s.io
{{- end }}
  labels:
    microsoft.azureorbital/serviceName: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
  name: {{ $volumeName }}-pv
  namespace: {{ $serviceValues.serviceNamespace }}
spec:
  capacity:
    storage: {{ $globalValues.xferDirectoryQuota }}
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
{{- if eq $globalValues.fileserverSMB true }}
  storageClassName: smb
  mountOptions:
    - dir_mode=0777
    - file_mode=0777
  csi:
    driver: smb.csi.k8s.io
    readOnly: false
    volumeHandle: {{ $volumeNameFQDN }}##
    volumeAttributes:
      source: "//{{ $volumeNameFQDN }}"
    nodeStageSecretRef:
      name: fileserver-{{ $serviceValues.appName }}
      namespace: {{ $serviceValues.serviceNamespace }}
{{- else }}
  storageClassName: local-path
  hostPath:
    {{- if and (eq $serviceValues.appName "hostsvc-link") (eq $volumeDirName "allxfer") }}
    path: {{ printf "%s/%s" $globalValues.spacefxDirectories.base $globalValues.spacefxDirectories.xfer }}
    {{- else }}
    path: {{ printf "%s/%s/%s" $globalValues.spacefxDirectories.base $volumeDirName $serviceValues.appName }}
    {{- end }}
    type: DirectoryOrCreate
{{- end }}
{{- end }}
{{- end }}

{{- define "spacefx.fileserver.persistentvolumeclaim" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $fileServerValues := .fileServerValues }}
{{- $volumesList := $globalValues.xferVolumes }}
{{- if $serviceValues.xferVolumes }}
{{- range $serviceVolumeKey, $serviceVolumeName := $serviceValues.xferVolumes }}
{{- $volumesList = append $volumesList $serviceVolumeName }}
{{- end }}
{{- end }}
{{- $first := true }}
{{- range $volumeKey, $volumeName := $volumesList }}
{{- if not $first }}
---
{{- else }}
{{- $first = false }}
{{- end }}
{{- $volumeName := printf "%s-%s" $serviceValues.appName $volumeName }}
{{- $volumeNameFQDN := printf "%s.%s.svc.cluster.local/%s" $fileServerValues.appName $fileServerValues.serviceNamespace $volumeName }}
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: {{ $volumeName }}-pvc
  namespace: {{ $serviceValues.serviceNamespace }}
  labels:
    microsoft.azureorbital/serviceName: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1M
    limits:
      storage: {{ $globalValues.xferDirectoryQuota }}
  volumeName: {{ $volumeName }}-pv
{{- if eq $globalValues.fileserverSMB true }}
  storageClassName: smb
{{- else }}
  storageClassName: local-path
{{- end }}
{{- end }}
{{- end }}


{{- define "spacefx.fileserver.clientapp.volumemount" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $volumeName := .volumeName }}
{{- $shareName := printf "%s-%s" $serviceValues.appName $volumeName }}
{{- $mountPath := printf "%s/%s/%s" $globalValues.spacefxDirectories.base $volumeName $serviceValues.appName }}
name: {{ $shareName | quote}}
{{- if and (eq $serviceValues.appName "hostsvc-link") (eq $volumeName "allxfer") }}
mountPath: {{ printf "%s/%s" $globalValues.spacefxDirectories.base $volumeName }}
{{- else }}
mountPath: {{ printf "%s/%s/%s" $globalValues.spacefxDirectories.base $volumeName $serviceValues.appName }}
{{- end }}
{{- end }}

{{- define "spacefx.fileserver.clientapp.volumemount.mountpath" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $volumeName := .volumeName }}
{{- $shareName := printf "%s-%s" $serviceValues.appName $volumeName }}
{{- $mountPath := printf "%s/%s/%s" $globalValues.spacefxDirectories.base $volumeName $serviceValues.appName }}
{{- if and (eq $serviceValues.appName "hostsvc-link") (eq $volumeName "allxfer") }}
{{ printf "%s/%s" $globalValues.spacefxDirectories.base $volumeName }}
{{- else }}
{{ printf "%s/%s/%s" $globalValues.spacefxDirectories.base $volumeName $serviceValues.appName }}
{{- end }}
{{- end }}


{{- define "spacefx.fileserver.clientapp.volume" }}
{{- $serviceValues := .serviceValues }}
{{- $volumeName := .volumeName }}
name: {{ $serviceValues.appName }}-{{ $volumeName }}
persistentVolumeClaim:
  claimName: {{ $serviceValues.appName }}-{{ $volumeName }}-pvc
{{- end }}