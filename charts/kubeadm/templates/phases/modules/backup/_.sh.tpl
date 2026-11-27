{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

# The backups of the certificates of the node to backup.dir.
# This module provides basic functions which are used by
# different modules and has a top-level backup function which
# calls the backup/restore functions of the modules as one operation

#!define: backup_files
# copies the files that exist on the node to the backup folder $1
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
# puts the files back from the backup folder $1
# if the backup file doesn't exist, removes the file on the node. The
# assumption is that the file didn't exist before the backup and appeared
# after it was taken
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

#!define: backup_exists_rc
# 0 if backup.dir exists
backup_exists_rc() {
  [ -e "${ROOTFS}{{ $envAll.Values.backup.dir }}" ]
}

#!define: backup
#!needs: certs_backup, kubelet_backup, kubeadm_backup
#!needs: certs_restore, kubelet_restore, kubeadm_restore
# the phase, its argument selects the action:
# 1. no argument - creates a new backup folder (a timestamp) in backup.dir and
#    backs up the certificates of the node to it,
# 2. restore - puts the certificates back from the latest backup,
# 3. remove - removes all the backups.
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
      # fails if there is no backup
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
