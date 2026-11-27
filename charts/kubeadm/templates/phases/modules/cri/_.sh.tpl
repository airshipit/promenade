{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

{{/* cri_sync_rc syncs the configuration of the container runtime from cri.fsgroup */}}
{{- tuple $envAll $mainDict "cri_sync_rc" $envAll.Values.cri.fsgroup | include "kubeadm.fs.render_fsgroup_sync_rc" -}}

#!define: cri_restart
# running containers survive the restart of containerd and CRI-O
cri_restart() {
  systemctl daemon-reload
  systemctl restart {{ $envAll.Values.cri.service | quote }}
}

#!define: cri_setup
#!needs: binary_cri_sync_rc, cri_sync_rc, cri_restart
# syncs the container runtime and its configuration and restarts it if they
# changed
cri_setup() {
  local cri_changed=false
  binary_cri_sync_rc && cri_changed=true
  cri_sync_rc && cri_changed=true
  if [[ $cri_changed == true ]]; then
    cri_restart
  fi
}
