{{- define "kubeadm.bundle.templateSettings" -}}
  {{- $dot := index . 0 -}}
  {{- $item := index . 1 -}}
  {{- $settings := index . 2 -}}

  {{- $_ := set $settings "mode" "override" -}}
  {{- if typeIs "string" $item -}}
      {{- $_ := set $settings "file" $item -}}
  {{- else -}}
      {{- $_ := set $settings "mode" (index $item 0) -}}
      {{- $_ := set $settings "file" (index $item 1) -}}
  {{- end -}}

  {{/* override means we try to find tpl and fallback to fs */}}
  {{- $mode := get $settings "mode" -}}
  {{- $file := get $settings "file" -}}
  {{- if eq $mode "override" -}}
    {{- $mode = "fs" -}}
    {{- if hasKey $dot.Values.bundle "tpl" -}}
      {{- if hasKey $dot.Values.bundle.tpl $file -}}
        {{- $mode = "tpl" -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $_ := set $settings "mode" $mode -}}
{{- end -}}


{{- define "kubeadm.bundle.templateActualMode" -}}
  {{- $dot := index . 0 -}}
  {{- $item := index . 1 -}}
  {{- $templateSettings := dict -}}
  {{- $_ := tuple $dot $item $templateSettings | include "kubeadm.bundle.templateSettings" -}}
  {{ get $templateSettings "mode" }}
{{- end -}}


{{- define "kubeadm.bundle.template" -}}
  {{- $dot := index . 0 -}}
  {{- $item := index . 1 -}}
  {{- $arg := $dot -}}
  {{- if gt (len .) 2 -}}
    {{- $arg = index . 2 -}}
  {{- end -}}

  {{- $templateSettings := dict -}}
  {{- $_ := tuple $dot $item $templateSettings | include "kubeadm.bundle.templateSettings" -}}
  {{- $mode := get $templateSettings "mode" -}}
  {{- $file := get $templateSettings "file" -}}

  {{/* Render template depending on the mode */}}
  {{- if eq $mode "include" -}}
      {{ include $file $arg }}
  {{- else if eq $mode "fs" -}}
    {{ include (printf "%s/%s" $dot.Chart.Name $file) $arg }}
  {{- else if eq $mode "tpl" -}}
    {{- tpl (index $dot.Values "bundle" "tpl" $file) $arg -}}
  {{- end -}}
{{- end -}}