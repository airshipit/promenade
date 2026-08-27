version = 2

[debug]
  level = "warn"

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = {{ .Values.images.tags.containerd_pause | quote }}

{{ if .Values.containerd.auths }}
[plugins."io.containerd.cri.v1.images".registry.auths]
{{- range $_,$v := .Values.containerd.auths }}
    [plugins."io.containerd.cri.v1.images".registry.auths.{{ $v.repo | quote }}]
        auth = {{ $v.auth | b64enc | quote }}
{{- end }}
{{- end }}

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true