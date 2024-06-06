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
{{- range $volumeKey, $volumeName := $volumesList }}
{{- $volumeName := printf "%s-%s" $serviceValues.appName $volumeName }}
{{- $volumeNameFQDN := printf "%s.%s.svc.cluster.local/%s" $fileServerValues.appName $fileServerValues.serviceNamespace $volumeName }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    pv.kubernetes.io/provisioned-by: smb.csi.k8s.io
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
  persistentVolumeReclaimPolicy: Delete
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
{{- range $volumeKey, $volumeName := $volumesList }}
{{- $volumeName := printf "%s-%s" $serviceValues.appName $volumeName }}
{{- $volumeNameFQDN := printf "%s.%s.svc.cluster.local/%s" $fileServerValues.appName $fileServerValues.serviceNamespace $volumeName }}
---
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
  storageClassName: smb
{{- end }}
{{- end }}


{{- define "spacefx.fileserver.clientapp.volumemount" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $volumeName := .volumeName }}
{{- $shareName := printf "%s-%s" $serviceValues.appName $volumeName }}
{{- $mountPath := printf "%s/%s/%s" $globalValues.spacefxDirectories.base $volumeName $serviceValues.appName }}
- name: {{ $shareName | quote}}
  mountPath: {{ $mountPath }}
{{- end }}

{{- define "spacefx.fileserver.clientapp.volume" }}
{{- $serviceValues := .serviceValues }}
{{- $volumeName := .volumeName }}
- name: {{ $serviceValues.appName }}-{{ $volumeName }}
  persistentVolumeClaim:
    claimName: {{ $serviceValues.appName }}-{{ $volumeName }}-pvc
{{- end }}