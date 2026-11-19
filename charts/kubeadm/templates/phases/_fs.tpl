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

{{- $_ := set $symbols "group_dir_files" (dict "body" `
# the files of the directory the group syncs (the same archives as
# group_dir_sync)
group_dir_files() {
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

{{/* the groups of the values: fs.groups.<group> is synced by fsgroup_<group>_sync_rc
     (templates/phases/snippets/common/_fs.tpl) */}}
{{- range $group,$list := ($envAll.Values.fs).groups | default dict -}}
  {{- tuple $envAll $k8sConfDict (printf "fsgroup_%s_sync_rc" $group) $list | include "kubeadm.fs.render_fsgroup_sync_rc" -}}
{{- end -}}
