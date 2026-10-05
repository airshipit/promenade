{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict "allNodes" -}}
{{- $perNode := get $k8sConfDict "perNode" -}}
{{- $_ := set $allNodes "kubelet" (dict "content" (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-service-default.tpl" | include "kubeadm.bundle.template") "dest_path" "etc/default/kubelet" "file_mode" 0600 ) -}}
{{- $_ := set $allNodes "kubelet.service" (dict "content"  (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-service.tpl" | include "kubeadm.bundle.template") "dest_path" "etc/systemd/system/kubelet.service" "file_mode" 0600 ) -}}
{{- if eq "tpl" (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-config.yaml" | include "kubeadm.bundle.templateActualMode") -}}
  {{- $_ := set $allNodes "kubelet_config.yaml" (dict "content"  (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-config.yaml" | include "kubeadm.bundle.template") "dest_path" "var/lib/kubelet/config.yaml" "file_mode" 0600 ) -}}
{{- end -}}

{{- if $envAll.Values.certs -}}

  {{- if $envAll.Values.certs.ca -}}
    {{- $_ := set $allNodes "kubeletpkipub_kubelet-client-ca.pem" (dict "content" $envAll.Values.certs.ca.crt "dest_path" "/etc/kubernetes/pki/kubelet-client-ca.pem" "file_mode" 0600 ) -}}
    {{- range $k,$v := $envAll.Values.certs.nodes -}}
      {{- $perNodeEntry := get $perNode $k | default (dict) -}}
      {{- $_ := set $perNode $k $perNodeEntry -}}
      {{- $_ := set $perNodeEntry "kubeletpkipub_kubelet.pem" (dict "content" $v.kubelet.crt "dest_path" "/etc/kubernetes/pki/kubelet.pem" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "kubeletpkipriv_kubelet-key.pem" (dict "content" $v.kubelet.key "dest_path" "/etc/kubernetes/pki/kubelet-key.pem" "file_mode" 0600) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}
{{- $_ := set $sharedLibs $sharedLibName (printf `
sync_kubelet_kubeconfig() {
  local pki_dir="${HOST_DIR}/etc/kubernetes/pki"
  local k_crt="${pki_dir}/kubelet.pem"
  local k_key="${pki_dir}/kubelet-key.pem"
  local k_conf="${ROOTFS}${HOST_DIR}/etc/kubernetes/kubelet.conf"
  local sha_before=$(sha256sum "$k_crt" "$k_key" "$k_conf" 2>/dev/null || true)

  ensure_dir "${ROOTFS}${pki_dir}" "%s" "%s"
  sync_prefix_based_dir "${ROOTFS}" "${pki_dir}" "kubeletpkipub_" "worker" false "%s" "%s"
  sync_prefix_based_dir "${ROOTFS}" "${pki_dir}" "kubeletpkipriv_" "worker" false "%s" "%s"

  ensure_dir "${ROOTFS}${HOST_DIR}/etc/kubernetes/" "%s" "%s"
  render_kubeconfig "$k_conf" \
    "%s" \
    "kubelet" \
    "/etc/kubernetes/pki/kubelet-client-ca.pem" \
    "/etc/kubernetes/pki/kubelet.pem" \
    "/etc/kubernetes/pki/kubelet-key.pem" "%s" "%s"

  local sha_after=$(sha256sum "$k_crt" "$k_key" "$k_conf" 2>/dev/null || true)

  [ "$sha_before" != "$sha_after" ] && return 0 || return 1
}

sync_kubelet() {
  local c=1 # return code 1 means false

  sync_kubelet_kubeconfig && c=0

  ensure_dir "${ROOTFS}${HOST_DIR}/etc/default/" "%s" "%s"
  envsubst < "${ROOTFS}/tmp/allnodes/kubelet" | compare_copy_file - "${ROOTFS}${HOST_DIR}/etc/default/kubelet" && c=0
  ensure_file "${ROOTFS}${HOST_DIR}/etc/default/kubelet" "%s" "%s"

  ensure_dir "${ROOTFS}${HOST_DIR}/etc/systemd/system/" "%s" "%s"
  compare_copy_file "${ROOTFS}/tmp/allnodes/kubelet.service" "${ROOTFS}${HOST_DIR}/etc/systemd/system/kubelet.service" && c=0
  ensure_file "${ROOTFS}${HOST_DIR}/etc/default/kubelet" "%s" "%s"

  ensure_dir "${ROOTFS}${HOST_DIR}/var/lib/kubelet/" "%s" "%s"
  [ -f "${ROOTFS}/tmp/allnodes/kubelet_config.yaml" ] && compare_copy_file "${ROOTFS}/tmp/allnodes/kubelet_config.yaml" "${ROOTFS}${HOST_DIR}/var/lib/kubelet/config.yaml" && c=0
  ensure_file "${ROOTFS}${HOST_DIR}/var/lib/kubelet/config.yaml" "%s" "%s"
  echo "kubelet is synced"
  return $c
}
`
(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki" "kubeletpkipub_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki" "kubeletpkipub_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki" "kubeletpkipriv_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki" "kubeletpkipriv_") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes") | include "kubeadm.bundle.template")
($envAll.Values.kubeconfig.controlPlaneEndpoint)
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes" "kubelet.conf") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes" "kubelet.conf") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/default") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/default") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/default" "kubelet") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/default" "kubelet") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/systemd/system") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/systemd/system") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/systemd/system" "kubelet.service") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/systemd/system" "kubelet.service") | include "kubeadm.bundle.template")


(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/var/lib/kubelet") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/var/lib/kubelet") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/var/lib/kubelet" "config.yaml") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/var/lib/kubelet" "config.yaml") | include "kubeadm.bundle.template")


) -}}