{{- define "spacefx.service_account" }}
{{- $serviceValues := .serviceValues }}
{{- $globalValues := .globalValues }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $serviceValues.appName | quote }}
  namespace: {{ $serviceValues.serviceNamespace | quote }}
{{- if eq $serviceValues.appName "platform-deployment" }}
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: cluster-admin
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: cluster-admin-binding
subjects:
- kind: ServiceAccount
  name: {{ $serviceValues.appName }}
  namespace: {{ $serviceValues.serviceNamespace }}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
{{- end }}
{{- end }}