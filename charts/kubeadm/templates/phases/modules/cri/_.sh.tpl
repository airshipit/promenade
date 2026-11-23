{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{/* cri_sync_rc: the configuration of the container runtime (cri.fsgroup) */}}
{{- tuple $envAll $k8sConfDict "cri_sync_rc" $envAll.Values.cri.fsgroup | include "kubeadm.fs.render_fsgroup_sync_rc" -}}

#!define: cri_restart
# Restarts the container runtime after binary_cri_sync_rc or cri_sync_rc changed it:
# Running containers survive the restart of containerd and CRI-O.
cri_restart() {
  systemctl daemon-reload
  systemctl restart {{ $envAll.Values.cri.service | quote }}
}

#!define: cri_setup
#!needs: binary_cri_sync_rc, cri_sync_rc, cri_restart
{{- /* binary_cri_sync_rc: binaries.sync.cri of the values */}}
# the container runtime and its configuration, restarted if they are changed
cri_setup() {
  local cri_changed=false
  binary_cri_sync_rc && cri_changed=true
  cri_sync_rc && cri_changed=true
  if [[ $cri_changed == true ]]; then
    cri_restart
  fi
}
