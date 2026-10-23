{{/* renders the template (tuple dot path arg [patchArg]) to yaml and applies
     to it the strategic merge patch bundle.tpl."<path>.patch" if it is defined,
     the patch is rendered with patchArg (arg by default). The schema is the one
     of the chart, the gvk is "<apiVersion>/<kind>" of the rendered template */}}
{{- define "kubeadm.bundle.patched_template" -}}
  {{- $dot := index . 0 -}}
  {{- $path := index . 1 -}}
  {{- $arg := index . 2 -}}
  {{- $patchArg := $arg -}}
  {{- if gt (len .) 3 -}}{{- $patchArg = index . 3 -}}{{- end -}}

  {{- $base := tuple $dot $path $arg | include "kubeadm.bundle.template" | fromYaml -}}
  {{- $patchPath := printf "%s.patch" $path -}}
  {{- if hasKey $dot.Values.bundle.tpl $patchPath -}}
    {{- $patch := tuple $dot $patchPath $patchArg | include "kubeadm.bundle.template" | fromYaml -}}
    {{- if not (and $base.apiVersion $base.kind) -}}
      {{- fail (printf "kubeadm.bundle.patched_template: %s has no apiVersion or kind" $path) -}}
    {{- end -}}
    {{- $schema := dict -}}
    {{- $_ := include "strategic_merge_patch_schema" $schema -}}
    {{- $out := dict -}}
    {{- $_ := include "strategic_merge_patch" (tuple $schema (printf "%s/%s" $base.apiVersion $base.kind) $base $patch $out) -}}
    {{- toYaml $out -}}
  {{- else -}}
    {{- toYaml $base -}}
  {{- end -}}
{{- end -}}
