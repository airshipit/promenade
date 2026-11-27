{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

{{/* os_sync_rc syncs the files of the operating system from os.fsgroup */}}
{{- tuple $envAll $mainDict "os_sync_rc" $envAll.Values.os.fsgroup | include "kubeadm.fs.render_fsgroup_sync_rc" -}}

#!define: os_setup
#!needs: os_sync_rc
# turns swap off, also in fstab, because kubelet doesn't start with it, and
# applies the kernel modules and sysctl of os.fsgroup when os_sync_rc changed
# them
os_setup() {
  swapoff -a
  sed "${SED_INPLACE[@]}" '/^[^#].* swap / s/^/#/' "${ROOTFS}/etc/fstab"
  if os_sync_rc; then
    systemctl restart systemd-modules-load.service
    sysctl --system
  fi
}
