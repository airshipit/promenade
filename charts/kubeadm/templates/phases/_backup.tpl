{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{/* the backups of the certificates of the node (backup.dir): every module
     backs up and restores its own groups (certs_backup, kubelet_backup,
     kubeadm_backup), the backups exist while a procedure is in progress (the
     rebootstrap), the reconcile waits for its end */}}

{{/* the helpers of the modules: <module>_backup, <module>_restore */}}
{{- $_ := set $symbols "backup_files" (dict "body" `
# copies the files (absolute paths of the node) the node has to the backup $1
backup_files() {
  local backup="$1" file
  shift
  for file in "$@"; do
    if [ -f "${ROOTFS}${file}" ]; then
      mkdir -p "${backup}${file%/*}"
      cp -p "${ROOTFS}${file}" "${backup}${file}"
    fi
  done
}
`) -}}

{{- $_ := set $symbols "restore_files" (dict "body" `
# puts the files back from the backup $1, removes the ones it doesn't have (the
# node didn't have them before)
restore_files() {
  local backup="$1" file
  shift
  for file in "$@"; do
    if [ -f "${backup}${file}" ]; then
      cp -p "${backup}${file}" "${ROOTFS}${file}"
    else
      rm -f "${ROOTFS}${file}"
    fi
  done
}
`) -}}

{{- $_ := set $symbols "group_dir_backup" (dict "needs" (list "backup_files" "group_dir_files")
"body" `
# copies the files of the directory the group syncs to the backup directory
group_dir_backup() {
  backup_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}
`) -}}

{{- $_ := set $symbols "group_dir_restore" (dict "needs" (list "restore_files" "group_dir_files")
"body" `
# puts the files of the group back from the backup directory, removes the ones
# it doesn't have (the node didn't have them before the sync)
group_dir_restore() {
  restore_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}
`) -}}

{{- define "__backup_exists_rc" -}}
{{- $envAll := . -}}
# 0 while backup.dir exists (reconcile_guard creates it before the first
# backup): the procedure isn't over (backup_restore or backup_remove)
backup_exists_rc() {
  [ -e "${ROOTFS}{{ $envAll.Values.backup.dir }}" ]
}
{{- end -}}
{{- $_ := set $symbols "backup_exists_rc" (dict
"body" (include "__backup_exists_rc" $envAll)
) -}}

{{- define "__backup" -}}
{{- $envAll := . -}}
# every run makes a new backup (<timestamp>) of the certificates of the node,
# they have the keys: backup_remove removes all of them when the procedure is
# over
backup() {
  local backup
  backup="${ROOTFS}{{ $envAll.Values.backup.dir }}/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p -m 0700 "${ROOTFS}{{ $envAll.Values.backup.dir }}" "${backup}"
  certs_backup "${backup}"
  kubelet_backup "${backup}"
  kubeadm_backup "${backup}"
  echo "the certificates are backed up to ${backup}"
}
{{- end -}}
{{- $_ := set $symbols "backup" (dict "needs" (list "certs_backup" "kubelet_backup" "kubeadm_backup")
"body" (include "__backup" $envAll)
) -}}

{{- define "__backup_restore" -}}
{{- $envAll := . -}}
# from the last backup or REBOOTSTRAP_BACKUP (<timestamp>)
backup_restore() {
  local dir="${ROOTFS}{{ $envAll.Values.backup.dir }}" backup
  backup="${REBOOTSTRAP_BACKUP:-$(ls -1 "${dir}" | tail -n 1)}"
  # it removes the files the backup doesn't have: not a wrong or empty name
  if [ -z "${backup}" ] || [ ! -d "${dir}/${backup}" ]; then
    echo "no backup '${backup}' in ${dir}" >&2
    return 1
  fi
  certs_restore "${dir}/${backup}"
  kubelet_restore "${dir}/${backup}"
  kubeadm_restore "${dir}/${backup}"
  echo "the certificates are restored from ${dir}/${backup}"
}
{{- end -}}
{{- $_ := set $symbols "backup_restore" (dict "needs" (list "certs_restore" "kubelet_restore" "kubeadm_restore")
"body" (include "__backup_restore" $envAll)
) -}}

{{- define "__backup_remove" -}}
{{- $envAll := . -}}
backup_remove() {
  rm -rf "${ROOTFS}{{ $envAll.Values.backup.dir }}"
  echo "the backups {{ $envAll.Values.backup.dir }} are removed"
}
{{- end -}}
{{- $_ := set $symbols "backup_remove" (dict
"body" (include "__backup_remove" $envAll)
) -}}
