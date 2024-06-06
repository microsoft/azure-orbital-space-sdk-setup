{{- define "spacefx.dataGenerator" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
{{- $imgName := printf "%s/%s:%s" (include "spacefx.dataGenerator.servicePrefixCalc" (dict "globalValues" $globalValues)) $serviceValues.repository $globalValues.spacefxVersion }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $serviceValues.repository | quote }}
  namespace: {{ $serviceValues.serviceNamespace | quote }}
spec:
  type: ClusterIP
  ports:
    - port: {{ $serviceValues.targetPort }}
      targetPort: {{ $serviceValues.targetPort }}
  selector:
    app: {{ $serviceValues.repository | quote }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $serviceValues.repository | quote }}
  namespace: {{ $serviceValues.serviceNamespace | quote }}
  labels:
    app: {{ $serviceValues.repository | quote }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ $serviceValues.repository | quote }}
  template:
    metadata:
      labels:
        app: {{ $serviceValues.repository | quote }}
    spec:
      containers:
      - name: {{ $serviceValues.repository | quote }}
        image: {{ $imgName | quote }}
        imagePullPolicy: IfNotPresent
        resources:
            limits:
              memory: {{ $globalValues.resources.memory.limit }}
              cpu: {{ $globalValues.resources.cpu.limit }}
            requests:
              memory: {{ $globalValues.resources.memory.request }}
              cpu: {{ $globalValues.resources.cpu.limit }}
{{- end }}