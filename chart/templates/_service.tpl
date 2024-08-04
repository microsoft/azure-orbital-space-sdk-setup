{{- define "spacefx.service" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $fileServerValues := .fileServerValues }}
{{- $buildServiceValues := .buildServiceValues }}
{{- $payloadAppValues := .payloadAppValues }}
---
{{- include "spacefx.appsettings.json" (dict "globalValues" $globalValues "serviceValues" $serviceValues) }}
---
{{- include "spacefx.secrets" (dict "globalValues" $globalValues "serviceValues" $serviceValues "fileServerValues" $fileServerValues "payloadAppValues" .payloadAppValues "buildServiceValues" $buildServiceValues) }}
{{- $imgName := printf "%s/%s:%s" (include "spacefx.servicePrefixCalc" (dict "globalValues" $globalValues)) $serviceValues.repository (include "spacefx.serviceVersionCalc" (dict "globalValues" $globalValues "serviceValues" $serviceValues)) }}
---
{{- include "spacefx.service_account" (dict "serviceValues" $serviceValues "globalValues" $globalValues) }}
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
      terminationGracePeriodSeconds: 1
      {{- if eq $serviceValues.appName "platform-mts" }}
      dnsPolicy: ClusterFirstWithHostNet
      hostNetwork: true
      {{- end }}
      {{- if $globalValues.security.forceNonRoot }}
{{- include "spacefx.initcontainers.setperms" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | indent 6 }}
      {{- end }}
      containers:
        - name: {{ $serviceValues.appName | quote }}
          {{- if $globalValues.security.forceNonRoot }}
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            runAsNonRoot: true
          {{- end }}
          ports:
          - name: app-port
            containerPort: 50051
        {{- if or $serviceValues.appHealthChecks $serviceValues.debugShim }}
          {{- if $globalValues.probes.liveness.enabled }}
          livenessProbe:
            grpc:
              port: 50051
            failureThreshold: {{ $globalValues.probes.liveness.failureThreshold }}
            periodSeconds: {{ $globalValues.probes.liveness.periodSeconds }}
            initialDelaySeconds: {{ $globalValues.probes.liveness.initialDelaySeconds }}
            timeoutSeconds: {{ $globalValues.probes.liveness.timeoutSeconds }}
          {{- end }}
          {{- if $globalValues.probes.startup.enabled }}
          startupProbe:
            grpc:
              port: 50051
            failureThreshold: {{ $globalValues.probes.startup.failureThreshold }}
            periodSeconds: {{ $globalValues.probes.startup.periodSeconds }}
            initialDelaySeconds: {{ $globalValues.probes.startup.initialDelaySeconds }}
            timeoutSeconds: {{ $globalValues.probes.startup.timeoutSeconds }}
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
          {{- $containerArgs := printf "%s/%s.dll" $serviceValues.workingDir $serviceValues.appName }}
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
{{- $secretsVolume := (include "spacefx.secrets.volume" (dict "globalValues" $globalValues "serviceValues" $serviceValues) | nindent 2 | trim) }}
{{- printf "- %s" $secretsVolume | nindent 8 }}
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