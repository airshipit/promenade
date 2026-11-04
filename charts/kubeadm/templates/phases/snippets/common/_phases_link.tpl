{{/* the functions of a script with phases (templates/bin/_bootstrap.tpl,
     _rebootstrap.tpl) linked (templates/lib/_linker.tpl), then its PHASES:
     (tuple $k8sConfDict <the symbols of the script> <the phases of the values>).
     The symbols of the script are always linked and win over the ones of
     templates/phases. A phase is a function */}}
{{- define "kubeadm.phases.link" -}}
{{- $k8sConfDict := index . 0 -}}
{{- $own := index . 1 -}}
{{- $phases := index . 2 -}}
{{- $symbols := dict -}}
{{- range $name, $symbol := get $k8sConfDict "symbols" -}}
  {{- $_ := set $symbols $name $symbol -}}
{{- end -}}
{{- range $name, $symbol := $own -}}
  {{- $_ := set $symbols $name $symbol -}}
{{- end -}}
{{- $needs := keys $own | sortAlpha -}}
{{- range $phase := $phases -}}
  {{- $needs = append $needs (trimPrefix "+" $phase) -}}
{{- end -}}
{{ include "linker" (dict "symbols" $symbols "needs" $needs) }}
PHASES=(
{{- range $phase := $phases }}
  {{ $phase | squote }}
{{- end }}
)
{{- end -}}
