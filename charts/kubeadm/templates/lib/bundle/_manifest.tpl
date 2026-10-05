{{- define "kubeadm.bundle.manifest" -}}
{{- $dot := index . 0 -}}
{{- $key := index . 1 -}}

{{/* check if the key doens't exist or true (true is default) */}}
{{- $render := true -}}
{{- if hasKey $dot.Values "manifests" -}}
  {{- if hasKey $dot.Values.manifests $key -}}
    {{- $render = index $dot.Values.manifests $key -}}
  {{- end -}}
{{- end -}}

{{/* render */}}
{{- if eq $render true -}}
    {{- $item := index $dot.Values.bundle.manifests $key -}}
    {{- if typeIs "string" $item -}}
      {{- include "kubeadm.bundle.template" (tuple $dot $item $dot) -}}
    {{- else if $item -}}
      {{- include "kubeadm.bundle.template" (tuple $dot (tuple (index $item 0) (index $item 1)) $dot) -}}
    {{- end -}}
{{- end -}}
{{- end -}}