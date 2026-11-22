{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{- define "__render_kubeconfig" -}}
{{- $envAll := . -}}
{{- $tpl := (tuple $envAll "templates/phases/modules/kubeconfig/_kubeconfig.yaml.tpl" | include "kubeadm.bundle.template") -}}
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
{{- end -}}

{{- define "__kubeconfigs_sync" -}}
{{- $envAll := . -}}
{{/*kubeconfigs permissions*/}}
{{- $dirMode := tuple $envAll "/etc/kubernetes" | include "kubeadm.fs.dir_mode" -}}
{{- $dirOwner := tuple $envAll "/etc/kubernetes" | include "kubeadm.fs.dir_owner" -}}
{{- $adminMode := tuple $envAll "kubeconfig" "admin.conf" | include "kubeadm.fs.file_mode" -}}
{{- $adminOwner := tuple $envAll "kubeconfig" "admin.conf" | include "kubeadm.fs.file_owner" -}}
{{- $ctrlMgrMode := tuple $envAll "kubeconfig" "controller-manager.conf" | include "kubeadm.fs.file_mode" -}}
{{- $ctrlMgrOwner := tuple $envAll "kubeconfig" "controller-manager.conf" | include "kubeadm.fs.file_owner" -}}
{{- $schdlrMode := tuple $envAll "kubeconfig" "scheduler.conf" | include "kubeadm.fs.file_mode" -}}
{{- $schdlrOwner := tuple $envAll "kubeconfig" "scheduler.conf" | include "kubeadm.fs.file_owner" -}}
kubeconfigs_sync() {

  if [ "${NODE_ROLE}" == "master" ]; then
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

{{- $_ := set $symbols "render_kubeconfig" (dict "needs" (list "subst_node_env" "compare_copy_file")
"body" (include "__render_kubeconfig" $envAll)
) -}}

{{- $_ := set $symbols "kubeconfigs_sync" (dict "needs" (list "ensure_dir" "render_kubeconfig")
"body" (include "__kubeconfigs_sync" $envAll)
) -}}
