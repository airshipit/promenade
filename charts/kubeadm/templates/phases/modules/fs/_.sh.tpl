{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

{{- $symbols := get $mainDict "symbols" -}}
{{- $all := get (get $mainDict "fs") "all" -}}

# To deliver each node only what it needs, the chart delivers its files in 4
# archives unpacked to /run/kubeadm: all, ctrl (control plane nodes only),
# all-pernode and ctrl-pernode (the files of the node). Each archive has a
# directory per group.

{{/* appends to the environment shared with the other modules */}}
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

{{/* generate fsgroup_<group>_sync_rc for each fs.groups.<group> of the
     values */}}
{{- range $group,$list := ($envAll.Values.fs).groups | default dict -}}
  {{- tuple $envAll $mainDict (printf "fsgroup_%s_sync_rc" $group) $list | include "kubeadm.fs.render_fsgroup_sync_rc" -}}
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
# copies $1 to $2 if they differ and sets the mode $3 and the owner $4. Reads
# stdin if $1 isn't a file. Returns 0 if $2 was changed and 1 if not
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
# replaces the ${NODE_*} placeholders with the values of the node
subst_node_env() {
  sed \
    -e "s|\${NODE_ROLE}|${NODE_ROLE:-}|g" \
    -e "s|\${NODE_NAME}|${NODE_NAME:-}|g" \
    -e "s|\${NODE_IP}|${NODE_IP:-}|g" "$@"
}

#!define: group_dir_files
# prints the paths on the node of the files group_dir_sync copies for the group
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
# prints the checksum of the files of the groups $3... group_dir_sync copies
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
# copies the files of the group from the archives to the directory $3,
# substituting the NODE_* variables if $5 is true
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
# copies the files group_dir_sync copies for the group to the backup $5
group_dir_backup() {
  backup_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}

#!define: group_dir_restore
# puts the files of the group back from the backup $5
group_dir_restore() {
  #!needs: restore_files, group_dir_files
  restore_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}
