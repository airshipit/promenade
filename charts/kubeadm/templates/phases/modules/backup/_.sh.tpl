{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

# The backups of the certificates of the node (backup.dir): every module backs
# up and restores its own groups (certs_backup, kubelet_backup,
# kubeadm_backup), the backups exist while a procedure is in progress (the
# rebootstrap), the reconcile waits for its end. backup_files, restore_files
# and the group_dir ones are the helpers of the modules for their
# <module>_backup and <module>_restore.

#!define: backup_files
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

#!define: restore_files
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

#!define: backup_exists_rc
# 0 while backup.dir exists (reconcile_guard creates it before the first
# backup): the procedure isn't over (backup restore or backup remove)
backup_exists_rc() {
  [ -e "${ROOTFS}{{ $envAll.Values.backup.dir }}" ]
}

#!define: backup
#!needs: certs_backup, kubelet_backup, kubeadm_backup
#!needs: certs_restore, kubelet_restore, kubeadm_restore
# the phase: a new backup (<timestamp>) of the certificates of the node, with
# "restore" the certificates of the last one back, with "remove" all the
# backups (they have the keys: the procedure is over, the reconcile goes on)
backup() {
  local dir="${ROOTFS}{{ $envAll.Values.backup.dir }}" backup
  case "${1:-}" in
    "")
      backup="${dir}/$(date -u +%Y%m%dT%H%M%SZ)"
      mkdir -p -m 0700 "${dir}" "${backup}"
      certs_backup "${backup}"
      kubelet_backup "${backup}"
      kubeadm_backup "${backup}"
      echo "the certificates are backed up to ${backup}"
      ;;
    restore)
      # fails without backups: restore removes the files the backup doesn't have
      backup=$(ls -1d "${dir}"/*/ | tail -n 1)
      certs_restore "${backup}"
      kubelet_restore "${backup}"
      kubeadm_restore "${backup}"
      echo "the certificates are restored from ${backup}"
      ;;
    remove)
      rm -rf "${dir}"
      echo "the backups ${dir} are removed"
      ;;
    *)
      echo "usage: backup [restore | remove]" >&2
      return 1
      ;;
  esac
}
