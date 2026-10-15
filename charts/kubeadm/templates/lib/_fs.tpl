{{/*
  The archives with the files of the chart (see templates/phases/_fs.tpl)
*/}}

{{/* "true" if the archive (tuple fs archive) has files, for any node in the per-node ones */}}
{{- define "kubeadm.fs.hasFiles" -}}
  {{- $files := get (index . 0) (index . 1) -}}
  {{- if hasSuffix "-pernode" (index . 1) -}}
    {{- range $_,$nodeFs := $files -}}
      {{- if $nodeFs -}}true{{- end -}}
    {{- end -}}
  {{- else if $files -}}true
  {{- end -}}
{{- end -}}

{{/* base64 of the tar of the files, constant mtime keeps the hashes in the daemonsets annotations */}}
{{- define "kubeadm.fs.archive_tar_b64" -}}
  {{- $files := dict -}}
  {{- range $k,$v := . -}}
    {{- $_ := set $files $k (merge (dict "mod_timestamp" 0) $v) -}}
  {{- end -}}
  {{- $files | include "tar" | b64enc -}}
{{- end -}}
