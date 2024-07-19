{{- define "spacefx.service" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $fileServerValues := .fileServerValues }}
{{- $buildServiceValues := .buildServiceValues }}
{{- $payloadAppValues := .payloadAppValues }}
{{- include "spacefx.appsettings.json" (dict "globalValues" $globalValues "serviceValues" $serviceValues) }}
{{- include "spacefx.secrets" (dict "globalValues" $globalValues "serviceValues" $serviceValues "fileServerValues" $fileServerValues "payloadAppValues" .payloadAppValues "buildServiceValues" $buildServiceValues) }}
{{- $imgName := printf "%s/%s:%s" (include "spacefx.servicePrefixCalc" (dict "globalValues" $globalValues)) $serviceValues.repository (include "spacefx.serviceVersionCalc" (dict "globalValues" $globalValues "serviceValues" $serviceValues)) }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $serviceValues.appName | quote }}
  namespace: {{ $serviceValues.serviceNamespace | quote }}
  labels:
    app: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
    microsoft.azureorbital/isDebugShim: {{ $serviceValues.debugShim | quote }}
    type: "Deployment"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ $serviceValues.appName | quote }}
      microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
      microsoft.azureorbital/isDebugShim: {{ $serviceValues.debugShim | quote }}
  template:
    metadata:
      name: {{ $serviceValues.appName | quote }}
      labels:
        app: {{ $serviceValues.appName | quote }}
        microsoft.azureorbital/appName: {{ $serviceValues.appName | quote }}
        microsoft.azureorbital/isDebugShim: {{ $serviceValues.debugShim | quote }}
      annotations:
{{- include "spacefx.daprannotations" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | indent 8 }}
    spec:
      serviceAccountName: {{  $serviceValues.appName | quote }}
      {{- if eq $serviceValues.appName "platform-mts" }}
      dnsPolicy: ClusterFirstWithHostNet
      hostNetwork: true
      {{- end }}
      containers:
        - name: {{ $serviceValues.appName | quote }}
        {{- if $serviceValues.securityContext }}
          securityContext:
        {{- range $index, $securityContext := $serviceValues.securityContext }}
            {{ $securityContext.name }}: {{ $securityContext.value }}
        {{- end }}
        {{- end }}
        {{- if $serviceValues.debugShim }}
          image: "{{ $serviceValues.repository }}:latest"
          imagePullPolicy: "Never"
          command: [{{ $globalValues.debugShim.command | quote }}]
          {{- $containerArgs := printf "%s/%s" $serviceValues.workingDir $globalValues.debugShim.keepAliveRelativePath }}
          args:
            - {{ $containerArgs }}
        {{- else }}
          {{- if or $serviceValues.containerArgs (hasKey $serviceValues "containerArgs") }}
            {{- if $serviceValues.containerArgs }}
          args: [
            {{- range $index, $containerArg := $serviceValues.containerArgs -}}
            {{ $containerArg | quote }}
            {{- if ne $index (sub (len $serviceValues.containerArgs) 1) }},{{ end }}
            {{- end -}}
            ]
            {{- end }}
          {{- else }}
          {{- $containerArgs := printf "/workspaces/%s/%s.dll" $serviceValues.appName $serviceValues.appName }}
          args: [{{ $containerArgs | quote }}]
          {{- end }}
          image: {{ $imgName | quote }}
          imagePullPolicy: {{ $globalValues.imagePullPolicy }}
          {{- if or $serviceValues.containerCommand (hasKey $serviceValues "containerCommand") }}
          {{- if $serviceValues.containerCommand }}
          command: [{{ $serviceValues.containerCommand | quote }}]
          {{- end }}
          {{- else }}
          command: [{{ $globalValues.containerCommand | quote }}]
          {{- end }}
          workingDir: {{ $serviceValues.workingDir | quote }}
        {{- end }}
          env:
            - name: SPACEFX_DIR
              value: {{ $globalValues.spacefxDirectories.base }}
            - name: SPACEFX_SECRET_DIR
              value: {{ $globalValues.spacefxSecretDirectory }}
            - name: DOTNET_SYSTEM_GLOBALIZATION_INVARIANT
              value: "1"
            - name: "DOTNET_USE_POLLING_FILE_WATCHER"
              value: "true"
            - name: "DOTNET_HOSTBUILDER__RELOADCONFIGONCHANGE"
              value: "false"
          {{- include "spacefx.resourceLimits" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | indent 10  }}
          volumeMounts:
{{- $appsettingsMount := printf "%s" (include "spacefx.appsettings.json.volumemount" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | nindent 2 | trim) }}
{{- printf "- %s" $appsettingsMount | nindent 12 }}
{{- $secretsMount := printf "%s" (include "spacefx.secrets.volumemount" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | nindent 2 | trim) }}
{{- printf "- %s" $secretsMount | nindent 12 }}
{{- range $volumeKey, $volumeName := $globalValues.xferVolumes }}
{{- $fileServerVolumeMount := printf "%s" (include "spacefx.fileserver.clientapp.volumemount" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | nindent 2 | trim) }}
{{- printf "- %s" $fileServerVolumeMount | nindent 12 }}
{{- end }}
{{- if $serviceValues.xferVolumes }}
{{- range $volumeKey, $volumeName := $serviceValues.xferVolumes }}
{{- $fileServerVolumeMount := printf "%s" (include "spacefx.fileserver.clientapp.volumemount" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | nindent 2 | trim) }}
{{- printf "- %s" $fileServerVolumeMount | nindent 12 }}
{{- end }}
{{- end }}
{{- if $serviceValues.debugShim }}
            - name: src-code
              mountPath: {{ $serviceValues.workingDir | quote }}
{{- end }}
{{- if $serviceValues.hostDirectoryMounts }}
{{- range $key, $hostDirectoryMount := $serviceValues.hostDirectoryMounts }}
            - name: {{ $hostDirectoryMount.name | lower }}
              mountPath: /host{{ $hostDirectoryMount.hostPath }}
{{- end }}
{{- end }}
      volumes:
{{- $appSettingsVolume := printf "%s" (include "spacefx.appsettings.json.volume" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | nindent 2 | trim) }}
{{- printf "- %s" $appSettingsVolume | nindent 8 }}
{{- $secretsMount := (include "spacefx.secrets.volume" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | nindent 2 | trim) }}
{{- printf "- %s" $secretsMount | nindent 8 }}
{{- range $volumeKey, $volumeName := $globalValues.xferVolumes }}
{{- $fileServerVolume := printf "%s" (include "spacefx.fileserver.clientapp.volume" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | nindent 2 | trim) }}
{{- printf "- %s" $fileServerVolume | nindent 8 }}
{{- end }}
{{- if $serviceValues.xferVolumes }}
{{- range $volumeKey, $volumeName := $serviceValues.xferVolumes }}
{{- $fileServerVolume := printf "%s" (include "spacefx.fileserver.clientapp.volume" (dict "globalValues" $globalValues "serviceValues" $serviceValues "volumeName" $volumeName) | nindent 2 | trim) }}
{{- printf "- %s" $fileServerVolume | nindent 8 }}
{{- end }}
{{- end }}
{{- if $serviceValues.debugShim }}
{{- $hostSourceCodeDir := $serviceValues.hostSourceCodeDir | required "service.hostSourceCodeDir is required." }}
        - name: src-code
          hostPath:
            path: {{ $hostSourceCodeDir | quote }}
            type: DirectoryOrCreate
{{- end }}
{{- if $serviceValues.hostDirectoryMounts }}
{{- range $key, $hostDirectoryMount := $serviceValues.hostDirectoryMounts }}
        - name: {{ $hostDirectoryMount.name | lower }}
          hostPath:
            path: {{ $hostDirectoryMount.hostPath | quote }}
            type: DirectoryOrCreate
{{- end }}
{{- end }}
{{- end }}