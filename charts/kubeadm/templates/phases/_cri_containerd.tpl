{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" }}
{{- define "__cri_containerd_lib_functions" -}}
{{- $envAll := . -}}
{{/* todo: can support configuring versions */}}
{{- $ver := .Values.containerd.version -}}

{{- $dirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/containerd") | include "kubeadm.bundle.template" -}}
{{- $dirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/containerd") | include "kubeadm.bundle.template" -}}
{{- $configMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/containerd" "config.toml") | include "kubeadm.bundle.template" -}}
{{- $configOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/containerd" "config.toml") | include "kubeadm.bundle.template" -}}

sync_cri() {
  # todo - can check sha256 before and after and restart if needed
  ensure_dir "${ROOTFS}${HOST_DIR}/etc/containerd/" "{{ $dirMode }}" "{{ $dirOwner }}"
  base64 -d << 'EOF_DATA' | compare_copy_file - "${ROOTFS}${HOST_DIR}/etc/containerd/config.toml" "{{ $configMode }}" "{{ $configOwner }}"
{{ tuple $envAll (printf "templates/phases/snippets/cri/_containerd_%s.tpl" $ver) | include "kubeadm.bundle.template" | b64enc}}
EOF_DATA
  echo "cri(containerd) is synced"
}

{{ end -}}

{{- $_ := set $sharedLibs $sharedLibName (include "__cri_containerd_lib_functions" $envAll) -}}