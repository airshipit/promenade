apiVersion: v1
clusters:
  - cluster:
      insecure-skip-tls-verify: false
      server: https://127.0.0.1:8443/webhook
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
