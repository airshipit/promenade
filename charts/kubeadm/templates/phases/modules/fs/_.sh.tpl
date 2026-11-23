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

{{/* the groups of the values: fs.groups.<group> is synced by fsgroup_<group>_sync_rc
     (templates/phases/modules/fs/_helpers.tpl) */}}
{{- range $group,$list := ($envAll.Values.fs).groups | default dict -}}
  {{- tuple $envAll $k8sConfDict (printf "fsgroup_%s_sync_rc" $group) $list | include "kubeadm.fs.render_fsgroup_sync_rc" -}}
{{- end -}}

#!define: ensure_dir
ensure_dir() {
  mkdir -p "$1"
  if [ -z "${SKIPPERM}" ]; then
    [ -n "$2" ] && chmod "$2" "$1"
    [ -n "$3" ] && chown "$3" "$1"
  fi
  return 0
}

#!define: ensure_file
ensure_file() {
  touch "$1"
  if [ -z "${SKIPPERM}" ]; then
    [ -n "$2" ] && chmod "$2" "$1"
    [ -n "$3" ] && chown "$3" "$1"
  fi
  return 0
}

#!define: compare_copy_file
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

#!define: subst_node_env
subst_node_env() {
  sed \
    -e "s|\${NODE_ROLE}|${NODE_ROLE:-}|g" \
    -e "s|\${NODE_NAME}|${NODE_NAME:-}|g" \
    -e "s|\${NODE_IP}|${NODE_IP:-}|g" "$@"
}

#!define: group_dir_files
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

#!define: _groups_sha256
# the checksum of the files of the groups $3... in the archives of the node, as
# group_dir_sync takes them (the ctrl archives on the control plane nodes only)
_groups_sha256() {
  local rootfs="$1" node_role="$2" group archive file
  shift 2
  for group in "$@"; do
    for archive in all ctrl all-pernode ctrl-pernode; do
      case "${archive}" in
        ctrl*) [ "${node_role}" == "master" ] || continue ;;
      esac
      for file in "${rootfs}/run/kubeadm/${archive}/${group}"/*; do
        [ -f "${file}" ] || continue
        sha256sum "${file}"
      done
    done
  done | sha256sum | cut -d ' ' -f 1
}

#!define: group_dir_sync
#!needs: compare_copy_file, subst_node_env
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

#!define: group_dir_backup
#!needs: backup_files, group_dir_files
# copies the files of the directory the group syncs to the backup directory
group_dir_backup() {
  backup_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}

#!define: group_dir_restore
# puts the files of the group back from the backup directory, removes the ones
# it doesn't have (the node didn't have them before the sync)
group_dir_restore() {
  #!needs: restore_files, group_dir_files
  restore_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}
