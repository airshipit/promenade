{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{- $all := get (get $k8sConfDict "fs") "all" -}}

{{/* the environment: appended, the other modules add theirs too */}}
{{- $environment := get $symbols "" | default (dict "body" "") -}}
{{- $_ := set $symbols "" (dict "body" (print $environment.body `
# cross-platform sha256 helper - needed for mac, TODO: remove it after testing
if ! command -v sha256sum >/dev/null 2>&1; then
  sha256sum() { shasum -a 256 "$@"; }
fi

# cross-platform flag in-place sed command
SED_INPLACE=(-i)
[ "$(uname)" = "Darwin" ] && SED_INPLACE=(-i '')

# for testing to avoid setting permissions in chroot
SKIPPERM="${SKIPPERM:-}"
`)) -}}

{{- $_ := set $symbols "ensure_dir" (dict "body" `
ensure_dir() {
  mkdir -p "$1"
  if [ -z "${SKIPPERM}" ]; then
    [ -n "$2" ] && chmod "$2" "$1"
    [ -n "$3" ] && chown "$3" "$1"
  fi
  return 0
}
`) -}}

{{- $_ := set $symbols "ensure_file" (dict "body" `
ensure_file() {
  touch "$1"
  if [ -z "${SKIPPERM}" ]; then
    [ -n "$2" ] && chmod "$2" "$1"
    [ -n "$3" ] && chown "$3" "$1"
  fi
  return 0
}
`) -}}

{{- $_ := set $symbols "compare_copy_file" (dict "body" `
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
`) -}}

{{- $_ := set $symbols "subst_node_env" (dict "body" `
subst_node_env() {
  sed \
    -e "s|\${NODE_ROLE}|${NODE_ROLE:-}|g" \
    -e "s|\${NODE_NAME}|${NODE_NAME:-}|g" \
    -e "s|\${NODE_IP}|${NODE_IP:-}|g" "$@"
}
`) -}}

{{- $_ := set $symbols "_group_dir_files" (dict "body" `
# the files of the directory the group syncs (the same archives as
# group_dir_sync)
_group_dir_files() {
  local rootfs="$1" group="$2" dir="$3" node_role="$4"
  local archive file
  for archive in all ctrl all-pernode ctrl-pernode; do
    case "${archive}" in
      ctrl*) [ "${node_role}" == "master" ] || continue ;;
    esac
    for file in "${rootfs}/run/kubeadm/${archive}/${group}"/*; do
      [ -f "$file" ] && echo "${dir}/${file##*/}"
    done
  done
  return 0
}
`) -}}

{{- $_ := set $symbols "group_dir_sync" (dict "needs" (list "compare_copy_file" "subst_node_env")
"body" `
# The chart delivers its files in 4 archives unpacked to /run/kubeadm/<archive>:
# all, ctrl (control plane nodes only), all-pernode and ctrl-pernode (the files
# of the node). Each archive contains <group>/<files of the group>.
#
# copies the files of the group from all the archives to the directory, with
# subst if needed (the ctrl archives are skipped on the workers)
group_dir_sync() {
  local rootfs="$1" group="$2"
  local dst_dir="${rootfs}$3" node_role="$4" do_subst="$5"
  local mode="${6:-}"
  local owner="${7:-}"
  local archive file
  for archive in all ctrl all-pernode ctrl-pernode; do
    case "${archive}" in
      ctrl*) [ "${node_role}" == "master" ] || continue ;;
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
`) -}}

{{/* files groups go to the "all" archive as <group>/<path>, "_" groups are the phases ones:
     _<group>_sync returns 0 if the files were changed, 1 if not */}}
{{- range $group,$list := $envAll.Values.files | default dict -}}
  {{- if hasPrefix "_" $group -}}{{ fail (printf "files group %s: groups starting with _ are reserved for the phases" $group) }}{{- end -}}
  {{- $needs := dict -}}
  {{- $body := printf `# the files group %s of the values (files.%s)
_%s_sync() {
  local host_dir="${ROOTFS}"
  local changed=1 # return code 1 means false
` $group $group $group -}}
  {{- range $i,$v := $list -}}
    {{- if not $v.path -}}{{ fail (printf "files group %s, item %d doesn't have path" $group $i) }}{{- end -}}
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
        {{- if not $v.from -}}{{ fail (printf "files group %s, item %d doesn't have \"from\" field" $group $i) }}{{- end -}}
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
          {{- $file := printf "%s/%s" $group (trimPrefix "/" $v.path) -}}
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
}` $body $group -}}
  {{- if hasKey $symbols (printf "_%s_sync" $group) -}}{{ fail (printf "files group %s: _%s_sync is a function of the chart" $group $group) }}{{- end -}}
  {{- $_ := set $symbols (printf "_%s_sync" $group) (dict "needs" (keys $needs | sortAlpha)
  "body" $body
  ) -}}
{{- end -}}
