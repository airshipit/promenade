{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{/* we put here some common code which is used by most of the modules */}}

{{- $staticPart := `
# cross-platform sha256 helper - needed for mac, TODO: remove it after testin
if ! command -v sha256sum >/dev/null 2>&1; then
  sha256sum() { shasum -a 256 "$@"; }
fi

# ross-platform flag in-place sed command
SED_INPLACE=(-i)
[ "$(uname)" = "Darwin" ] && SED_INPLACE=(-i '')

# for testing to avoid setting permissions in chroot
SKIPPERM="${SKIPPERM:-}"

ensure_dir() {
  mkdir -p "$1"
  if [ -z "${SKIPPERM}" ]; then
    [ -n "$2" ] && chmod "$2" "$1"
    [ -n "$3" ] && chown "$3" "$1"
  fi
  return 0
}

ensure_file() {
  touch "$1"
  if [ -z "${SKIPPERM}" ]; then
    [ -n "$2" ] && chmod "$2" "$1"
    [ -n "$3" ] && chown "$3" "$1"
  fi
  return 0
}

compare_copy_file() {
  local src="$1" dst="$2"
  local mode="${3:-}"
  local owner="${4:-}"
  local delete_src=false
  local changed=1 # return code 1 means false

  if [ ! -f "$src" ]; then
    src=$(mktemp)
    cat - > "$src"
    delete_src=true
  fi

  if [ ! -e "$dst" ] || ! cmp -s "$src" "$dst"; then
    cp "$src" "$dst"
    changed=0
  fi

  if [ -z "${SKIPPERM}" ]; then
    [ -n "$mode" ] && chmod "$mode" "$dst"
    [ -n "$owner" ] && chown "$owner" "$dst"
  fi

  [ "$delete_src" = true ] && rm -f "$src"
  return $changed
}

#  universal configurable unpacker for dirs
#  takes actual folder path and unique files prefix for it
#  it can also do envsubst if needed
sync_prefix_based_dir() {
  local rootfs="$1"
  local nodes_dirs_dir="${rootfs}/tmp" dst_dir="${rootfs}$2" prefix="$3" node_role="$4" do_envsubst="$5"
  local mode="${6:-}"
  local owner="${7:-}"
  for dir in "${nodes_dirs_dir}/allnodes" "${nodes_dirs_dir}/ctrlnodes" "${nodes_dirs_dir}/per-node"; do
    [ -d "$dir" ] || continue
    [ "$dir" = "${nodes_dirs_dir}/ctrlnodes" ] && [ "$node_role" != "master" ] && continue
    for file in "$dir"/${prefix}*; do
      [ -e "$file" ] || continue
      local src_name="${file##*/}" # basename
      if [ "$do_envsubst" != "true" ]; then
        compare_copy_file "$file" "${dst_dir}/${src_name#$prefix}" "$mode" "$owner" || true
      else
        envsubst < "$file" | compare_copy_file - "${dst_dir}/${src_name#$prefix}" "$mode" "$owner" || true
      fi
    done
  done
}

%s
` -}}

{{- $generatedPart := "" -}}
{{- if $envAll.Values.files -}}
  {{- range $group,$list := $envAll.Values.files -}}
    {{- $generatedPart = printf `%ssync_%s() {
  local host_dir="${ROOTFS}${HOST_DIR}"
` $generatedPart $group -}}
    {{- range $i,$v := $list -}}
      {{- if not $v.path -}}{{ fail (printf "files item %d doesn't have path" $i) }}{{- end -}}
      {{- if or (eq $v.state "rm") (eq $v.state "remove") -}}
        {{- $generatedPart = printf `%s  rm "${host_dir}%s"
` $generatedPart $v.path -}}
      {{- else -}}
        {{- $owner := $v.owner | default "" -}}
        {{- $mode := $v.mode | default "" -}}
        {{- if eq $v.state "dir" -}}
          {{- $generatedPart = printf `%s  ensure_dir "${host_dir}%s" "%s" "%s"
` $generatedPart $v.path $owner $mode -}}
          {{- else if eq $v.state "touch" -}}
          {{- $generatedPart = printf `%s  ensure_file "${host_dir}%s" "%s" "%s"
` $generatedPart $v.path $owner $mode -}}
          {{- else -}}
            {{- if not $v.from -}}{{ fail (printf "files item %d doesn't have \"from\" field" $i) }}{{- end -}}
            {{- if or (eq $v.state "cp") (eq $v.state "copy") -}}
              {{- $generatedPart = printf `%s  compare_copy_file "${host_dir}%s" "${host_dir}%s" "%s" "%s"
` $generatedPart $v.from $v.path $owner $mode -}}
            {{- else if eq $v.state "content" -}}
              {{- $generatedPart = printf `%s  base64 -d << 'EOF_DATA' | compare_copy_file "-" "${host_dir}%s" "%s" "%s"
%s
EOF_DATA
` $generatedPart $v.path $owner $mode ($v.from | b64enc) -}}
            {{- else if eq $v.state "tpl" -}}
            {{- $generatedPart = printf `%s  base64 -d << 'EOF_DATA' | compare_copy_file "-" "${host_dir}%s" "%s" "%s"
%s
EOF_DATA
` $generatedPart $v.path $owner $mode (tuple $envAll $v.from | include "kubeadm.bundle.template" | b64enc) -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
      {{/* bash doesn't like empty functions */}}
      {{- $generatedPart = printf `%s  echo "%s is synced"
}
` $generatedPart $group -}}
    {{- end -}}
  {{- end -}}
{{- $_ := set $sharedLibs $sharedLibName (printf $staticPart $generatedPart ) }}