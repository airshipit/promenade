{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{/* os_sync_rc: the files of the operating system (os.fsgroup) */}}
{{- tuple $envAll $k8sConfDict "os_sync_rc" $envAll.Values.os.fsgroup | include "kubeadm.fs.render_fsgroup_sync_rc" -}}

#!define: os_setup
#!needs: os_sync_rc
# swap off (kubelet doesn't start with it), the kernel modules and sysctl of
# os.fsgroup applied when os_sync_rc changed them: the runtime needs overlay,
# the pod network br_netfilter and forwarding
os_setup() {
  swapoff -a
  sed "${SED_INPLACE[@]}" '/^[^#].* swap / s/^/#/' "${ROOTFS}/etc/fstab"
  if os_sync_rc; then
    systemctl restart systemd-modules-load.service
    sysctl --system
  fi
}
