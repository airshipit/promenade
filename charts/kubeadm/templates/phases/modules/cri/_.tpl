{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{/* cri_sync_rc: the configuration of the container runtime (cri.fsgroup) */}}
{{- tuple $envAll $k8sConfDict "cri_sync_rc" $envAll.Values.cri.fsgroup | include "kubeadm.fs.render_fsgroup_sync_rc" -}}

{{- define "__cri_restart" -}}
{{- $envAll := . -}}
# Restarts the container runtime after cri_install_sync_rc or cri_sync_rc changed it:
# always by the bootstrap script, with cri.restart by the reconcile script.
# Running containers survive the restart of containerd and CRI-O.
cri_restart() {
  systemctl daemon-reload
  systemctl restart {{ $envAll.Values.cri.service | quote }}
}
{{- end -}}
{{- $_ := set $symbols "cri_restart" (dict "body" (include "__cri_restart" $envAll)) -}}
