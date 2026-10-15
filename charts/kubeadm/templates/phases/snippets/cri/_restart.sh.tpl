# Restarts the container runtime after install_cri or the files.cri group
# changed it: always by the bootstrap script, with cri.restart by the reconcile
# script. Running containers survive the restart of containerd and CRI-O.
restart_cri() {
  systemctl daemon-reload
  systemctl restart {{ .Values.cri.service | quote }}
}
