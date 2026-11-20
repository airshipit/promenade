# Installs the container runtime of cri.service. Runs on the node: by the
# bootstrap script and, with cri.reconcile_install, by the reconcile script on
# the host. The runtime is restarted after it when it was changed.
# Returns 0 if the runtime was changed, 1 if not, exits on errors.
cri_install_sync_rc() {
  if ! systemctl cat {{ .Values.cri.service | quote }} > /dev/null 2>&1; then
    echo "{{ .Values.cri.service }} isn't found: install the runtime on the node or redefine cri_install_sync_rc in bundle.tpl" >&2
    exit 1
  fi
  return 1
}
