version = 3

[debug]
    level = "warn"

[plugins."io.containerd.cri.v1.images"]
    use_local_image_pull = true

[plugins."io.containerd.cri.v1.images".pinned_images]
    sandbox = {{ .Values.images.tags.containerd_pause | quote }}

    [plugins."io.containerd.cri.v1.images".registry]
    config_path = "/etc/containerd/certs.d"

{{ if .Values.containerd.auths }}
[plugins."io.containerd.cri.v1.images".registry.auths]
{{- range $_,$v := .Values.containerd.auths }}
    [plugins."io.containerd.cri.v1.images".registry.auths.{{ $v.repo | quote }}]
        auth = {{ $v.auth | b64enc | quote }}
{{- end }}
{{- end }}


[plugins."io.containerd.cri.v1.runtime".containerd]
    default_runtime_name = "runc"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"

    [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]
    SystemdCgroup = true
    Rlimits = [
        { type = "RLIMIT_NOFILE", soft = 131072, hard = 524288 },
    ]