{{/*
  the helpers of the files of the chart: the archives, the groups and the
  permissions
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

{{/* base64 of the tar of the files. The constant mtime keeps the hashes in the
     annotations of the daemonsets stable */}}
{{- define "kubeadm.fs.archive_tar_b64" -}}
  {{- $files := dict -}}
  {{- range $k,$v := . -}}
    {{- $_ := set $files $k (merge (dict "mod_timestamp" 0) $v) -}}
  {{- end -}}
  {{- $files | include "tar" | b64enc -}}
{{- end -}}

{{/* generates the function <function> syncing the files of the list as a
     symbol of the linker, the argument is
     (tuple envAll mainDict function list). An item has path,
     state (dir, touch, rm/remove, cp/copy, content, tpl), from, owner and
     mode. The content and tpl files go to the "all" archive as
     <function>/<path>. The function returns 0 if the files were changed and
     1 if not, so its name ends with _rc */}}
{{- define "kubeadm.fs.render_fsgroup_sync_rc" -}}
  {{- $envAll := index . 0 -}}
  {{- $mainDict := index . 1 -}}
  {{- $fn := index . 2 -}}
  {{- $list := index . 3 | default list -}}
  {{- $symbols := get $mainDict "symbols" -}}
  {{- $all := get (get $mainDict "fs") "all" -}}
  {{- if hasKey $symbols $fn -}}{{ fail (printf "%s is already defined" $fn) }}{{- end -}}
  {{- $needs := dict -}}
  {{- $body := printf `
%s() {
  local host_dir="${ROOTFS}"
  local changed=1 # return code 1 means false
` $fn -}}
  {{- range $i,$v := $list -}}
    {{- if not $v.path -}}{{ fail (printf "%s: item %d doesn't have path" $fn $i) }}{{- end -}}
    {{- if or (eq $v.state "rm") (eq $v.state "remove") -}}
      {{- $body = printf `%s  rm -f "${host_dir}%s"
` $body $v.path -}}
    {{- else -}}
      {{- $owner := $v.owner | default "" -}}
      {{- $mode := $v.mode | default "" -}}
      {{- if eq $v.state "dir" -}}
        {{- $_ := set $needs "ensure_dir" true -}}
        {{- $body = printf `%s  ensure_dir "${host_dir}%s" "%s" "%s"
` $body $v.path $mode $owner -}}
      {{- else if eq $v.state "touch" -}}
        {{- $_ := set $needs "ensure_file" true -}}
        {{- $body = printf `%s  ensure_file "${host_dir}%s" "%s" "%s"
` $body $v.path $mode $owner -}}
      {{- else -}}
        {{- if not $v.from -}}{{ fail (printf "%s: item %d doesn't have \"from\" field" $fn $i) }}{{- end -}}
        {{/* compare_copy_file returns 1 when the file is unchanged */}}
        {{- if or (eq $v.state "cp") (eq $v.state "copy") -}}
          {{- $_ := set $needs "compare_copy_file" true -}}
          {{- $body = printf `%s  compare_copy_file "${host_dir}%s" "${host_dir}%s" "%s" "%s" && changed=0
` $body $v.from $v.path $mode $owner -}}
        {{- else if or (eq $v.state "content") (eq $v.state "tpl") -}}
          {{- $data := $v.from -}}
          {{- if eq $v.state "tpl" -}}
            {{- $data = tuple $envAll $v.from | include "kubeadm.bundle.template" -}}
          {{- end -}}
          {{- $file := printf "%s/%s" $fn (trimPrefix "/" $v.path) -}}
          {{- $_ := set $all $file (dict "content" $data "file_mode" 384) -}}
          {{- $_ := set $needs "compare_copy_file" true -}}
          {{- $body = printf `%s  compare_copy_file "${host_dir}/run/kubeadm/all/%s" "${host_dir}%s" "%s" "%s" && changed=0
` $body $file $v.path $mode $owner -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{/* bash doesn't like empty functions */}}
  {{- $body = printf `%s  echo "%s is synced"
  return $changed
}
` $body $fn -}}
  {{- $_ := set $symbols $fn (dict "needs" (keys $needs | sortAlpha)
  "body" $body
  ) -}}
{{- end -}}

{{/* the mode of a directory from fs.permissions.<path>, the argument is
     (tuple envAll path) */}}
{{- define "kubeadm.fs.dir_mode" -}}
  {{- $envAll := index . 0 -}}
  {{- $path := index . 1 -}}
  {{- dig "permissions" $path "mode" "" ($envAll.Values.fs | default dict) -}}
{{- end -}}

{{- define "kubeadm.fs.dir_owner" -}}
  {{- $envAll := index . 0 -}}
  {{- $path := index . 1 -}}
  {{- dig "permissions" $path "owner" "" ($envAll.Values.fs | default dict) -}}
{{- end -}}

{{/* the mode of a group of the files of a module from
     <module>.permissions.<group>, the argument is (tuple envAll module group) */}}
{{- define "kubeadm.fs.file_mode" -}}
  {{- $envAll := index . 0 -}}
  {{- $phase := index . 1 -}}
  {{- $group := index . 2 -}}
  {{- dig "permissions" $group "mode" "" (index $envAll.Values $phase | default dict) -}}
{{- end -}}

{{- define "kubeadm.fs.file_owner" -}}
  {{- $envAll := index . 0 -}}
  {{- $phase := index . 1 -}}
  {{- $group := index . 2 -}}
  {{- dig "permissions" $group "owner" "" (index $envAll.Values $phase | default dict) -}}
{{- end -}}
