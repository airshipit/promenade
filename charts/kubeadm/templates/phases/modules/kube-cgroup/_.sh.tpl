{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

#!define: kube_cgroup_sync_rc
#!needs: ensure_dir, compare_copy_file
{{- $usrDirMode := tuple $envAll "/usr/local/sbin" | include "kubeadm.fs.dir_mode" }}
{{- $usrDirOwner := tuple $envAll "/usr/local/sbin" | include "kubeadm.fs.dir_owner" }}
{{- $scriptMode := tuple $envAll "kube_cgroup" "kube-cgroup.sh" | include "kubeadm.fs.file_mode" }}
{{- $scriptOwner := tuple $envAll "kube_cgroup" "kube-cgroup.sh" | include "kubeadm.fs.file_owner" }}
{{- $etcDirMode := tuple $envAll "/etc/systemd/system" | include "kubeadm.fs.dir_mode" }}
{{- $etcDirOwner := tuple $envAll "/etc/systemd/system" | include "kubeadm.fs.dir_owner" }}
{{- $serviceMode := tuple $envAll "kube_cgroup" "kube-cgroup.service" | include "kubeadm.fs.file_mode" }}
{{- $serviceOwner := tuple $envAll "kube_cgroup" "kube-cgroup.service" | include "kubeadm.fs.file_owner" }}
kube_cgroup_sync_rc() {
  local c=1 # return code 1 means false

  ensure_dir "${ROOTFS}/usr/local/sbin/" "{{ $usrDirMode }}" "{{ $usrDirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}/usr/local/sbin/kube-cgroup.sh" "{{ $scriptMode }}" "{{ $scriptOwner }}" && c=0
{{ tuple $envAll "templates/phases/modules/kube-cgroup/_kube-cgroup.sh.tpl" | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  ensure_dir "${ROOTFS}/etc/systemd/system/" "{{ $etcDirMode }}" "{{ $etcDirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}/etc/systemd/system/kube-cgroup.service" "{{ $serviceMode }}" "{{ $serviceOwner }}" && c=0
{{ tuple $envAll "templates/phases/modules/kube-cgroup/_kube-cgroup.service.tpl" | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  echo "kube-cgroup is synced"
  return $c
}

#!define: kube_cgroup_setup
#!needs: kube_cgroup_sync_rc
kube_cgroup_setup() {
  if kube_cgroup_sync_rc; then
    systemctl daemon-reload
    systemctl enable kube-cgroup.service
  fi
}
