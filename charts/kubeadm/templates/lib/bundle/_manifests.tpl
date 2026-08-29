{{- define "kubeadm.bundle.manifests" -}}
{{- $dot := . -}}
{{- $debug := $dot.Values.bundle.debug | default false -}}
{{ range $key, $val := $dot.Values.bundle.manifests }}
{{- if $debug }}
# === BUNDLE MANIFEST START: {{ $key }} [mode: {{ printf "%v" $val }}] ===
{{- end }}
{{ include "kubeadm.bundle.manifest" (tuple $dot $key) }}
{{- if $debug }}
# === BUNDLE MANIFEST END: {{ $key }} ===
{{- end }}
{{- end -}}
{{- end -}}