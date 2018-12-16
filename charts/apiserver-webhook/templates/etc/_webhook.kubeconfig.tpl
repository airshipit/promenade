apiVersion: v1
clusters:
  - cluster:
      insecure-skip-tls-verify: false
      server: https://127.0.0.1:{{ tuple "webhook_apiserver" "podport" "webhook" . | include "helm-toolkit.endpoints.endpoint_port_lookup" }}/webhook
      certificate-authority: {{ tuple "keystone_webhook" "server" .Values.conf.paths.pki "ca" . | include "local.cert_bundle_path" | quote }}
    name: webhook
contexts:
  - context:
      cluster: webhook
      user: webhook
    name: webhook
current-context: webhook
kind: Config
preferences: {}
users:
  - name: webhook
