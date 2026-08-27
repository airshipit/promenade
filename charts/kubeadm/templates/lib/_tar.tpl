{{/*
tar generates a valid USTAR formatted archive containing specified files.

Input: map of path -> file info dict:
  "path/to/file":
    type:             "0"        # 0: file, 1: hardlink, 2: symlink (default: "0")
    content:          "string"   # File payload (default: "")
    link_path:        "path"     # Target path for links (default: "")
    file_mode:        0644       # Octal file permissions (default: 0644)
    owner_uid:        0765       # Owner UID octal (default: 0765)
    group_uid:        024        # Group GID octal (default: 024)
    owner_user_name:  "user"     # Owner name, max 32 bytes (default: "user")
    owner_group_name: "group"    # Group name, max 32 bytes (default: "group")
    mod_timestamp:    12345678   # Unix modification timestamp (default: now)
    filename_prefix:  ""         # Manual USTAR prefix override (max 155 bytes)

Features:
  - Calculates 2-pass header checksums internally.
  - Automatically splits paths >100 bytes into USTAR prefix (155 bytes) and name (100 bytes).
  - Pads content to 512-byte blocks and appends a 1024-byte null EOF trailer.

Example:

{{- $envAll := . }}
{{- $files := dict
    "README" (dict "content" "Hi everyone!!!\n" "file_mode" 420)
    "README.symlink" (dict "type" "2" "link_path" "README" "file_mode" 511)
    "README.hardlink" (dict "type" "1" "link_path" "README" "file_mode" 420)
    "someverylongdir/someverylongdir/someverylongdir/someverylongdir/someverylongdir/someverylongdir/cluster_config.yaml" (dict "content" (tuple . "templates/kubeadm/_cluster_config.yaml.tpl" | include "kubeadm.bundle.template")  "file_mode" 420)
    "join_config.yaml" (dict "content" (tuple . "templates/kubeadm/_join_config.yaml.tpl" | include "kubeadm.bundle.template")  "file_mode" 420)
    "upgrade_config.yaml" (dict "content" (tuple . "templates/kubeadm/_upgrade_config.yaml.tpl" | include "kubeadm.bundle.template")  "file_mode" 420)
-}}

---
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "kubeadm.fullname" $envAll }}-aio-config-tar
type: Opaque
data:
  aio-config.tar: {{ $files | include "tar" | b64enc | quote }}

*/}}

{{- define "_tar_split_path" -}}
{{- $tarContextDict := index . 0 -}}

{{- $path := index . 1 -}}
{{- $prefix := "" -}}

  {{- if gt (len $path) 100 -}}
    {{- $tmp := $path -}}
    {{- $prefix = dir $tmp -}}
    {{- $path = base $tmp -}}

    {{- $done := false -}}
    {{- range $_ := until 50 -}}
      {{- if not $done -}}
        {{- $proposedPrefix := dir $prefix -}}
        {{- $proposedPath := printf "%s/%s" (base $prefix) $path -}}
        {{- if or (eq $proposedPrefix ".") (eq $proposedPrefix "/") (eq $prefix $proposedPrefix) (gt (len $proposedPath) 100) -}}
          {{- $done = true -}}
        {{- else -}}
          {{- $prefix = $proposedPrefix -}}
          {{- $path = $proposedPath -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}

    {{- if or (gt (len $path) 100) (gt (len $prefix) 155) (eq $prefix ".") -}}
      {{ fail (printf "Path '%s' cannot be split using dir/base (prefix max 155, name max 100)" $path) }}
    {{- end -}}

  {{- end -}}
  {{- $_ := set $tarContextDict "path" $path -}}
  {{- $_ := set $tarContextDict "prefix" $prefix -}}
{{- end -}}

{{- define "_tar_header" -}}
{{- $tarContextDict := index . 0 -}}

{{/* params to encode */}}

{{- $file_path_and_name := index . 1 -}}
{{- $info := index . 2 -}}
{{- $filename_prefix := get $info "filename_prefix" | default "" -}}

{{/* optional splitting into path/prefix (will work only if path is long) */}}
{{- if eq $filename_prefix "" -}}
  {{- tuple $tarContextDict $file_path_and_name | include "_tar_split_path" -}}
  {{- $file_path_and_name = get $tarContextDict "path" -}}
  {{- $filename_prefix = get $tarContextDict "prefix" -}}
{{- end -}}
{{- if gt (len $file_path_and_name) 100 -}}{{ fail "File path and name length exceeds 100 bytes limit" }}{{- end -}}
{{- if gt (len $filename_prefix) 155 -}}{{ fail "Filename prefix length exceeds 155 bytes limit" }}{{- end -}}

{{- $checksum := index . 3 -}}
{{- if gt (len $checksum) 8 -}}{{ fail "Checksum length exceeds 8 bytes limit" }}{{- end -}}

{{- $content := get $info "content" | default "" -}}
{{- $type := get $info "type" | default "0" | toString -}}
{{- if gt (len $type) 1 -}}{{ fail "type length exceeds 1 bytes limit" }}{{- end -}}
{{- if and (gt (len $content) 0) (ne $type "0") (ne $type "7") -}}{{ fail (printf "Content provided for non normal type %s" $file_path_and_name) }}{{- end -}}

{{- $link_path := get $info "link_path" | default "" -}}
{{- if gt (len $link_path) 100 -}}
  {{ fail (printf "link_path '%s' exceeds 100 bytes limit" $link_path) }}
{{- end -}}
{{- if and (or (eq $type "1") (eq $type "2")) (eq (len $link_path) 0) -}}
  {{ fail (printf "link_path is required for link type '%s' in '%s'" $type $file_path_and_name) }}
{{- end -}}

{{- $file_mode := get $info "file_mode" | default 0644 -}}
{{- if or (lt $file_mode 0) (gt $file_mode 511) -}}
  {{ fail (printf "file_mode '%v' is invalid. Expected octal range 0000-0777 (0-511 dec)" $file_mode) }}
{{- end -}}

{{- $owner_uid := get $info "owner_uid" | default 0765 -}}
{{- if or (lt $owner_uid 0) (gt $owner_uid 262143) -}}
  {{ fail (printf "owner_uid '%v' exceeds 6-octal digits limit (max 262143)" $owner_uid) }}
{{- end -}}

{{- $group_uid := get $info "group_uid" | default 024 -}}
{{- if or (lt $group_uid 0) (gt $group_uid 262143) -}}
  {{ fail (printf "group_uid '%v' exceeds 6-octal digits limit (max 262143)" $group_uid) }}
{{- end -}}

{{- $owner_user_name := get $info "owner_user_name" | default "user" -}}
{{- if gt (len $owner_user_name) 32 -}}{{ fail "Owner user name length exceeds 32 bytes limit" }}{{- end -}}

{{- $owner_group_name := get $info "owner_group_name" | default "group" -}}
{{- if gt (len $owner_group_name) 32 -}}{{ fail "Owner group name length exceeds 32 bytes limit" }}{{- end -}}

{{- $device_major := get $info "device_major" | default 0 -}}
{{- if or (lt $device_major 0) (gt $device_major 262143) -}}
  {{ fail (printf "device_major '%v' exceeds 6-octal digits limit (max 262143 dec / 0777777 oct)" $device_major) }}
{{- end -}}

{{- $device_minor := get $info "device_minor" | default 0 -}}
{{- if or (lt $device_minor 0) (gt $device_minor 262143) -}}
  {{ fail (printf "device_minor '%v' exceeds 6-octal digits limit (max 262143 dec / 0777777 oct)" $device_minor) }}
{{- end -}}

{{- $mod_timestamp := get $info "mod_timestamp" | default (get $tarContextDict "mod_timestamp") -}}

{{/* populate data */}}
{{- printf $file_path_and_name -}}
{{- $paddingLen := sub 100 (len $file_path_and_name) -}}
{{- repeat (int $paddingLen) (printf "%c" 0) -}}
{{- printf "%06o " $file_mode -}}
{{- printf "%c" 0 -}}
{{- printf "%06o " $owner_uid -}}
{{- printf "%c" 0 -}}
{{- printf "%06o " $group_uid -}}
{{- printf "%c" 0 -}}
{{- printf "%011o " (len $content) -}}
{{- printf "%011o " $mod_timestamp -}}

{{- printf $checksum -}}
{{- $paddingLen := sub 8 (len $checksum) -}}
{{- repeat (int $paddingLen) (printf "%c" 0) -}}

{{/* link indicator */}}
{{- printf $type -}}
{{- printf $link_path -}}
{{- $paddingLen := sub 100 (len $link_path) -}}
{{- repeat (int $paddingLen) (printf "%c" 0) -}}

{{/* ustar subheader version 00 */}}
{{- printf "ustar" -}}
{{- printf "%c" 0 -}}
{{- printf "00" -}}

{{- printf $owner_user_name -}}
{{- $paddingLen := sub 32 (len $owner_user_name) -}}
{{- repeat (int $paddingLen) (printf "%c" 0) -}}

{{- printf $owner_group_name -}}
{{- $paddingLen := sub 32 (len $owner_group_name) -}}
{{- repeat (int $paddingLen) (printf "%c" 0) -}}

{{- printf "%06o " $device_major -}}
{{- printf "%c" 0 -}}
{{- printf "%06o " $device_minor -}}
{{- printf "%c" 0 -}}

{{- printf $filename_prefix -}}
{{- $paddingLen := sub 155 (len $filename_prefix) -}}
{{- repeat (int $paddingLen) (printf "%c" 0) -}}

{{- repeat (int 12) (printf "%c" 0) -}}
{{- end -}}



{{- define "_tar_header_calc_checksum_and_print" -}}
{{- $tarContextDict := index . 0 -}}
{{- $tarHeader := index . 1 -}}

{{- if not (hasKey $tarContextDict "hexMap") -}}
  {{- $hexMap := dict -}}
  {{- range $i := until 256 -}}
    {{- $_ := set $hexMap (printf "%02x" $i) $i -}}
  {{- end -}}
  {{- $_ := set $tarContextDict "hexMap" $hexMap -}}
{{- end -}}
{{- $hexMap := get $tarContextDict "hexMap" -}}

{{- $hexStr := printf "%x" $tarHeader -}}

{{- $len := len $hexStr -}}
{{- $numBytes := div $len 2 | int -}}

{{- $current := 0 -}}
{{- range $i := until $numBytes -}}
  {{- $idx := mul $i 2 | int -}}
  {{- $byteHex := substr $idx (add $idx 2 | int) $hexStr -}}
  {{- $byteVal := get $hexMap $byteHex -}}
  {{- $current = add $current $byteVal -}}
{{- end -}}
{{- $_ := set $tarContextDict "sum" $current -}}

{{/* print buf, but with caclulated sum  */}}
{{- print (substr 0 148 $tarHeader) -}}
{{- printf "%06o%c " $current 0 -}}
{{- print (substr 156 (len $tarHeader) $tarHeader) -}}
{{- end -}}



{{- define "_tar_section" -}}
{{- $tarContextDict := index . 0 -}}
{{- $file_path_and_name := index . 1 -}}
{{- $info := index . 2 -}}
{{/* important: store time once so when we recalc sum we could get the same result*/}}
{{- $tarContextDict := dict "sum" 0 "mod_timestamp" (now | unixEpoch | int) -}}
{{- $tarHeader := tuple $tarContextDict $file_path_and_name $info "        " | include "_tar_header" -}}
{{- tuple $tarContextDict $tarHeader | include "_tar_header_calc_checksum_and_print" -}}
{{- $content := get $info "content" | default "" -}}
{{- print $content -}}
{{- $mod := mod (len $content) 512 -}}
{{- if gt $mod 0 -}}
  {{- repeat (int (sub 512 $mod)) (printf "%c" 0) -}}
{{- end -}}
{{- end -}}


{{- define "_tar_section_ensure_content" -}}
{{- $tarContextDict := index . 0 -}}
{{- $file_path_and_name := index . 1 -}}
{{- $info := index . 2 -}}

{{- $completedFiles := get $tarContextDict "completedFiles" | default (dict) -}}
{{- $_ := set $tarContextDict "completedFiles" $completedFiles -}}
{{- if not (hasKey $completedFiles $file_path_and_name) -}}

  {{/* make sure that content goes prio hardlinks(type == 1), prevent recursion */}}
  {{- $stack := get $tarContextDict "stack" | default (dict) -}}
  {{- $_ := set $tarContextDict "stack" $stack -}}
  {{- if hasKey $stack $file_path_and_name -}}{{ fail (printf "Recursive call for %s" $file_path_and_name) }}{{- end -}}
  {{- $_ := set $stack $file_path_and_name true -}}

  {{- $type := get $info "type" | default "0" | toString -}}
  {{- $link_path := get $info "link_path" | default "" -}}

  {{- if eq $type "1" -}}
    {{- $files := get $tarContextDict "files" -}}
    {{- if not (and $files (hasKey $files $link_path)) -}}{{ fail (printf "Files don't contain %s referenced by hardlink %s" $link_path $file_path_and_name) }}{{- end -}}
    {{- include "_tar_section_ensure_content" (tuple $tarContextDict $link_path (get $files $link_path)) -}}
  {{- end -}}

  {{- if not (hasKey $completedFiles $file_path_and_name) -}}
    {{- include "_tar_section" (tuple $tarContextDict $file_path_and_name $info) -}}
    {{- $_ := set $completedFiles $file_path_and_name true -}}
  {{- end -}}

  {{- $_ := unset $stack $file_path_and_name -}}
{{- end -}}
{{- end -}}


{{- define "tar" -}}
{{- $files := . -}}
{{- range $name, $info := $files -}}
  {{- include "_tar_section_ensure_content" (tuple (dict "files" $files) $name $info) -}}
{{- end -}}
{{/* ustar end of everything */}}
{{- repeat 1024 (printf "%c" 0) -}}
{{- end -}}
