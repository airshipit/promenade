# Restarts the container runtime after cri_install or the files.cri group
# changed it: always by the bootstrap script, with cri.restart by the reconcile
# script. Running containers survive the restart of containerd and CRI-O.
cri_restart() {
  systemctl daemon-reload
  systemctl restart {{ .Values.cri.service | quote }}
}
