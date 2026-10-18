{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{- define "__kubeconfig_lib_functions" -}}
{{- $envAll := . -}}
{{- $tpl := (tuple $envAll "templates/phases/snippets/kubeconfig/_kubeconfig.yaml.tpl" | include "kubeadm.bundle.template") -}}
{{/*kubeconfigs permissions*/}}
{{- $dirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes") | include "kubeadm.bundle.template" -}}
{{- $dirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes") | include "kubeadm.bundle.template" -}}
{{- $adminMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes" "admin.conf") | include "kubeadm.bundle.template" -}}
{{- $adminOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes" "admin.conf") | include "kubeadm.bundle.template" -}}
{{- $ctrlMgrMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes" "controller-manager.conf") | include "kubeadm.bundle.template" -}}
{{- $ctrlMgrOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes" "controller-manager.conf") | include "kubeadm.bundle.template" -}}
{{- $schdlrMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes" "scheduler.conf") | include "kubeadm.bundle.template" -}}
{{- $schdlrOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes" "scheduler.conf") | include "kubeadm.bundle.template" -}}

render_kubeconfig() {
  local dst="$1" ep="$2" user="$3" ca="$4" cert="$5" key="$6" mode="$7" owner="$8"
  cat << 'EOF_TEMPLATE_DATA' | subst_node_env \
      -e "s|\${CLUSTER_ENDPOINT}|${ep}|g" \
      -e "s|\${USER}|${user}|g" \
      -e "s|\${CERT_AUTH}|${ca}|g" \
      -e "s|\${CLIENT_CERT}|${cert}|g" \
      -e "s|\${CLIENT_KEY}|${key}|g" | compare_copy_file - "$dst" "$mode" "$owner" || true
{{ $tpl }}
EOF_TEMPLATE_DATA
}

sync_kubeconfigs() {

  if [[ "$NODE_ROLE" == "master" ]]; then
    ensure_dir "${ROOTFS}/etc/kubernetes/" "{{ $dirMode }}" "{{ $dirOwner }}"
{{- /* without pregenerated client certs kubeadm generates kubeconfigs itself */}}
{{- if ($envAll.Values.certs).admin }}
    render_kubeconfig "${ROOTFS}/etc/kubernetes/admin.conf" \
      "{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}" \
      "admin" \
      "/etc/kubernetes/admin/pki/cluster-ca.pem"  \
      "/etc/kubernetes/admin/pki/admin.pem" \
      "/etc/kubernetes/admin/pki/admin-key.pem" "{{ $adminMode }}" "{{ $adminOwner }}"
{{- end }}
{{- if ($envAll.Values.certs).controller_manager }}

    render_kubeconfig "${ROOTFS}/etc/kubernetes/controller-manager.conf" \
      "{{ $envAll.Values.kubeconfig.controlPlaneLocalEndpoint | default $envAll.Values.kubeconfig.controlPlaneEndpoint }}" \
      "controller-manager" \
      "pki/ca.crt"  \
      "pki/controller-manager.pem" \
      "pki/controller-manager-key.pem" "{{ $ctrlMgrMode }}" "{{ $ctrlMgrOwner }}"
{{- end }}
{{- if ($envAll.Values.certs).scheduler }}

    render_kubeconfig "${ROOTFS}/etc/kubernetes/scheduler.conf" \
      "{{ $envAll.Values.kubeconfig.controlPlaneLocalEndpoint | default $envAll.Values.kubeconfig.controlPlaneEndpoint }}" \
      "scheduler" \
      "pki/ca.crt"  \
      "pki/scheduler.pem" \
      "pki/scheduler-key.pem" "{{ $schdlrMode }}" "{{ $schdlrOwner }}"
{{- end }}
  fi

  echo "kubeconfigs are synced"
}

{{- end -}}
{{- $_ := set $sharedLibs $sharedLibName (include "__kubeconfig_lib_functions" $envAll) -}}
