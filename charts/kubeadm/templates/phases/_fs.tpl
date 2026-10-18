{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}
{{- $all := get (get $k8sConfDict "fs") "all" -}}

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

subst_node_env() {
  sed \
    -e "s|\${KUBEADM_TOKEN}|${KUBEADM_TOKEN:-}|g" \
    -e "s|\${NODE_ROLE}|${NODE_ROLE:-}|g" \
    -e "s|\${NODE_NAME}|${NODE_NAME:-}|g" \
    -e "s|\${NODE_IP}|${NODE_IP:-}|g" "$@"
}

# The chart delivers its files in 4 archives unpacked to /run/kubeadm/<archive>:
# all, ctrl (control plane nodes only), all-pernode and ctrl-pernode (the files
# of the node). Each archive contains <group>/<files of the group>.

# copies the files of the group from all the archives to the directory, with
# subst if needed (the ctrl archives are skipped on the workers)
sync_group_dir() {
  local rootfs="$1" group="$2"
  local dst_dir="${rootfs}$3" node_role="$4" do_subst="$5"
  local mode="${6:-}"
  local owner="${7:-}"
  local archive file
  for archive in all ctrl all-pernode ctrl-pernode; do
    case "${archive}" in
      ctrl*) [ "$node_role" = "master" ] || continue ;;
    esac
    for file in "${rootfs}/run/kubeadm/${archive}/${group}"/*; do
      [ -f "$file" ] || continue
      if [ "$do_subst" != "true" ]; then
        compare_copy_file "$file" "${dst_dir}/${file##*/}" "$mode" "$owner" || true
      else
        subst_node_env "$file" | compare_copy_file - "${dst_dir}/${file##*/}" "$mode" "$owner" || true
      fi
    done
  done
}


%s
` -}}

{{/* files groups go to the "all" archive as <group>/<path>, "_" groups are the phases ones */}}
{{- $generatedPart := "" -}}
{{- if $envAll.Values.files -}}
  {{- range $group,$list := $envAll.Values.files -}}
    {{- if hasPrefix "_" $group -}}{{ fail (printf "files group %s: groups starting with _ are reserved for the phases" $group) }}{{- end -}}
    {{- $generatedPart = printf `%ssync_%s() {
  local host_dir="${ROOTFS}"
  local changed=1 # return code 1 means false
` $generatedPart $group -}}
    {{- range $i,$v := $list -}}
      {{- if not $v.path -}}{{ fail (printf "files item %d doesn't have path" $i) }}{{- end -}}
      {{- if or (eq $v.state "rm") (eq $v.state "remove") -}}
        {{- $generatedPart = printf `%s  rm -f "${host_dir}%s"
` $generatedPart $v.path -}}
      {{- else -}}
        {{- $owner := $v.owner | default "" -}}
        {{- $mode := $v.mode | default "" -}}
        {{- if eq $v.state "dir" -}}
          {{- $generatedPart = printf `%s  ensure_dir "${host_dir}%s" "%s" "%s"
` $generatedPart $v.path $mode $owner -}}
          {{- else if eq $v.state "touch" -}}
          {{- $generatedPart = printf `%s  ensure_file "${host_dir}%s" "%s" "%s"
` $generatedPart $v.path $mode $owner -}}
          {{- else -}}
            {{- if not $v.from -}}{{ fail (printf "files item %d doesn't have \"from\" field" $i) }}{{- end -}}
            {{/* compare_copy_file returns 1 when the file is unchanged */}}
            {{- if or (eq $v.state "cp") (eq $v.state "copy") -}}
              {{- $generatedPart = printf `%s  compare_copy_file "${host_dir}%s" "${host_dir}%s" "%s" "%s" && changed=0
` $generatedPart $v.from $v.path $mode $owner -}}
            {{- else if or (eq $v.state "content") (eq $v.state "tpl") -}}
              {{- $data := $v.from -}}
              {{- if eq $v.state "tpl" -}}
                {{- $data = tuple $envAll $v.from | include "kubeadm.bundle.template" -}}
              {{- end -}}
              {{- $file := printf "%s/%s" $group (trimPrefix "/" $v.path) -}}
              {{- $_ := set $all $file (dict "content" $data "file_mode" 384) -}}
              {{- $generatedPart = printf `%s  compare_copy_file "${host_dir}/run/kubeadm/all/%s" "${host_dir}%s" "%s" "%s" && changed=0
` $generatedPart $file $v.path $mode $owner -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
      {{/* bash doesn't like empty functions */}}
      {{- $generatedPart = printf `%s  echo "%s is synced"
  return $changed
}
` $generatedPart $group -}}
    {{- end -}}
  {{- end -}}
{{- $_ := set $sharedLibs $sharedLibName (printf $staticPart $generatedPart ) }}
