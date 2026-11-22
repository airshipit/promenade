{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{- define "__kube_cgroup_sync" -}}
{{- $envAll := . -}}

{{- $usrDirMode := tuple $envAll "/usr/local/sbin" | include "kubeadm.fs.dir_mode" -}}
{{- $usrDirOwner := tuple $envAll "/usr/local/sbin" | include "kubeadm.fs.dir_owner" -}}
{{- $scriptMode := tuple $envAll "kube_cgroup" "kube-cgroup.sh" | include "kubeadm.fs.file_mode" -}}
{{- $scriptOwner := tuple $envAll "kube_cgroup" "kube-cgroup.sh" | include "kubeadm.fs.file_owner" -}}

{{- $etcDirMode := tuple $envAll "/etc/systemd/system" | include "kubeadm.fs.dir_mode" -}}
{{- $etcDirOwner := tuple $envAll "/etc/systemd/system" | include "kubeadm.fs.dir_owner" -}}
{{- $serviceMode := tuple $envAll "kube_cgroup" "kube-cgroup.service" | include "kubeadm.fs.file_mode" -}}
{{- $serviceOwner := tuple $envAll "kube_cgroup" "kube-cgroup.service" | include "kubeadm.fs.file_owner" -}}

kube_cgroup_sync() {
  ensure_dir "${ROOTFS}/usr/local/sbin/" "{{ $usrDirMode }}" "{{ $usrDirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}/usr/local/sbin/kube-cgroup.sh" "{{ $scriptMode }}" "{{ $scriptOwner }}" || true
{{ tuple $envAll "templates/phases/modules/kube-cgroup/_kube-cgroup.sh.tpl" | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  ensure_dir "${ROOTFS}/etc/systemd/system/" "{{ $etcDirMode }}" "{{ $etcDirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}/etc/systemd/system/kube-cgroup.service" "{{ $serviceMode }}" "{{ $serviceOwner }}" || true
{{ tuple $envAll "templates/phases/modules/kube-cgroup/_kube-cgroup.service.tpl" | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  echo "kube-cgroup is synced"
}
{{ end -}}

{{- $_ := set $symbols "kube_cgroup_sync" (dict "needs" (list "ensure_dir" "compare_copy_file")
"body" (include "__kube_cgroup_sync" $envAll)
) -}}
