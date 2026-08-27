{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" }}
{{- define "__kube_cgroup_lib_functions" -}}
{{- $envAll := . -}}

{{- $usrDirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/usr/local/sbin") | include "kubeadm.bundle.template" -}}
{{- $usrDirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/usr/local/sbin") | include "kubeadm.bundle.template" -}}
{{- $scriptMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/usr/local/sbin" "kube-cgroup.sh") | include "kubeadm.bundle.template" -}}
{{- $scriptOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/usr/local/sbin" "kube-cgroup.sh") | include "kubeadm.bundle.template" -}}

{{- $etcDirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/systemd/system") | include "kubeadm.bundle.template" -}}
{{- $etcDirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/systemd/system") | include "kubeadm.bundle.template" -}}
{{- $serviceMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/systemd/system" "kube-cgroup.service") | include "kubeadm.bundle.template" -}}
{{- $serviceOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/systemd/system" "kube-cgroup.service") | include "kubeadm.bundle.template" -}}

sync_kube_cgroup() {
  ensure_dir "${ROOTFS}${HOST_DIR}/usr/local/sbin/" "{{ $usrDirMode }}" "{{ $usrDirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}${HOST_DIR}/usr/local/sbin/kube-cgroup.sh" "{{ $scriptMode }}" "{{ $scriptOwner }}"
{{ tuple $envAll "templates/phases/snippets/kube-cgroup/_kube-cgroup.sh.tpl" | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  ensure_dir "${ROOTFS}${HOST_DIR}/etc/systemd/system/" "{{ $etcDirMode }}" "{{ $etcDirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}${HOST_DIR}/etc/systemd/system/kube-cgroup.service" "{{ $serviceMode }}" "{{ $serviceOwner }}"
{{ tuple $envAll "templates/phases/snippets/kube-cgroup/_kube-cgroup.service.tpl" | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  echo "kube-cgroup is synced"
}

{{ end -}}

{{- $_ := set $sharedLibs $sharedLibName (include "__kube_cgroup_lib_functions" $envAll) -}}