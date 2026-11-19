{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $allNodes := get (get $k8sConfDict "fs") "all" -}}
{{- $perNode := get (get $k8sConfDict "fs") "all-pernode" -}}
{{- $_ := set $allNodes "_kubelet/kubelet" (dict "content" (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-service-default.tpl" | include "kubeadm.bundle.template") "dest_path" "etc/default/kubelet" "file_mode" 0600 ) -}}
{{- $_ := set $allNodes "_kubelet/kubelet.service" (dict "content"  (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-service.tpl" | include "kubeadm.bundle.template") "dest_path" "etc/systemd/system/kubelet.service" "file_mode" 0600 ) -}}
{{- if eq "tpl" (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-config.yaml" | include "kubeadm.bundle.templateActualMode") -}}
  {{- $_ := set $allNodes "_kubelet/kubelet_config.yaml" (dict "content"  (tuple $envAll "templates/phases/snippets/kubelet/_kubelet-config.yaml" | include "kubeadm.bundle.template") "dest_path" "var/lib/kubelet/config.yaml" "file_mode" 0600 ) -}}
{{- end -}}

{{- if $envAll.Values.certs -}}

  {{- if $envAll.Values.certs.ca -}}
    {{- $_ := set $allNodes "_kubeletpkipub/kubelet-client-ca.pem" (dict "content" $envAll.Values.certs.ca.crt "dest_path" "/etc/kubernetes/pki/kubelet-client-ca.pem" "file_mode" 0600 ) -}}
    {{- range $k,$v := $envAll.Values.certs.nodes -}}
      {{- $perNodeEntry := get $perNode $k | default (dict) -}}
      {{- $_ := set $perNode $k $perNodeEntry -}}
      {{- $_ := set $perNodeEntry "_kubeletpkipub/kubelet.pem" (dict "content" $v.kubelet.crt "dest_path" "/etc/kubernetes/pki/kubelet.pem" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "_kubeletpkipriv/kubelet-key.pem" (dict "content" $v.kubelet.key "dest_path" "/etc/kubernetes/pki/kubelet-key.pem" "file_mode" 0600) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{- define "__kubelet_kubeconfig_sync_rc" -}}
{{- $envAll := . -}}
{{/* without pregenerated kubelet certs kubeadm generates kubelet.conf itself */}}
{{- $kubeletCerts := false -}}
{{- range $_,$v := ($envAll.Values.certs).nodes -}}
  {{- if $v.kubelet -}}{{- $kubeletCerts = true -}}{{- end -}}
{{- end -}}
{{- $kubernetesPkiDirMode := tuple $envAll "/etc/kubernetes/pki" | include "kubeadm.fs.dir_mode" -}}
{{- $kubernetesPkiDirOwner := tuple $envAll "/etc/kubernetes/pki" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeletpkipubMode := tuple $envAll "kubelet" "kubeletpkipub" | include "kubeadm.fs.file_mode" -}}
{{- $kubeletpkipubOwner := tuple $envAll "kubelet" "kubeletpkipub" | include "kubeadm.fs.file_owner" -}}
{{- $kubeletpkiprivMode := tuple $envAll "kubelet" "kubeletpkipriv" | include "kubeadm.fs.file_mode" -}}
{{- $kubeletpkiprivOwner := tuple $envAll "kubelet" "kubeletpkipriv" | include "kubeadm.fs.file_owner" -}}
{{- $kubernetesDirMode := tuple $envAll "/etc/kubernetes" | include "kubeadm.fs.dir_mode" -}}
{{- $kubernetesDirOwner := tuple $envAll "/etc/kubernetes" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeletConfMode := tuple $envAll "kubelet" "kubelet.conf" | include "kubeadm.fs.file_mode" -}}
{{- $kubeletConfOwner := tuple $envAll "kubelet" "kubelet.conf" | include "kubeadm.fs.file_owner" -}}
# returns 0 if the files were changed, 1 if not
kubelet_kubeconfig_sync_rc() {
  local pki_dir="/etc/kubernetes/pki"
  local k_crt="${ROOTFS}${pki_dir}/kubelet.pem"
  local k_key="${ROOTFS}${pki_dir}/kubelet-key.pem"
  local k_conf="${ROOTFS}/etc/kubernetes/kubelet.conf"
  local sha_before=$(sha256sum "$k_crt" "$k_key" "$k_conf" 2>/dev/null || true)

  ensure_dir "${ROOTFS}${pki_dir}" "{{ $kubernetesPkiDirMode }}" "{{ $kubernetesPkiDirOwner }}"
  group_dir_sync "${ROOTFS}" "_kubeletpkipub" "${pki_dir}" "worker" false "{{ $kubeletpkipubMode }}" "{{ $kubeletpkipubOwner }}"
  group_dir_sync "${ROOTFS}" "_kubeletpkipriv" "${pki_dir}" "worker" false "{{ $kubeletpkiprivMode }}" "{{ $kubeletpkiprivOwner }}"

  ensure_dir "${ROOTFS}/etc/kubernetes/" "{{ $kubernetesDirMode }}" "{{ $kubernetesDirOwner }}"
  if [ "{{ ternary "true" "false" $kubeletCerts }}" == "true" ]; then
    render_kubeconfig "$k_conf" \
      "{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}" \
      "kubelet" \
      "/etc/kubernetes/pki/kubelet-client-ca.pem" \
      "/etc/kubernetes/pki/kubelet.pem" \
      "/etc/kubernetes/pki/kubelet-key.pem" "{{ $kubeletConfMode }}" "{{ $kubeletConfOwner }}"
  elif [ -f "$k_conf" ]; then
    # kubeadm points kubelet to the endpoint the node joined via
    sed "${SED_INPLACE[@]}" -e "s|^\( *server:\).*|\1 https://{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}|" "$k_conf"
  fi

  local sha_after=$(sha256sum "$k_crt" "$k_key" "$k_conf" 2>/dev/null || true)

  [ "$sha_before" != "$sha_after" ] && return 0 || return 1
}
{{- end -}}
{{- $_ := set $symbols "kubelet_kubeconfig_sync_rc" (dict "needs" (list "ensure_dir" "group_dir_sync" "render_kubeconfig")
"body" (include "__kubelet_kubeconfig_sync_rc" $envAll)
) -}}

{{- define "__kubelet_sync_rc" -}}
{{- $envAll := . -}}
{{- $defaultDirMode := tuple $envAll "/etc/default" | include "kubeadm.fs.dir_mode" -}}
{{- $defaultDirOwner := tuple $envAll "/etc/default" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeletMode := tuple $envAll "kubelet" "kubelet" | include "kubeadm.fs.file_mode" -}}
{{- $kubeletOwner := tuple $envAll "kubelet" "kubelet" | include "kubeadm.fs.file_owner" -}}
{{- $systemdSystemDirMode := tuple $envAll "/etc/systemd/system" | include "kubeadm.fs.dir_mode" -}}
{{- $systemdSystemDirOwner := tuple $envAll "/etc/systemd/system" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeletServiceMode := tuple $envAll "kubelet" "kubelet.service" | include "kubeadm.fs.file_mode" -}}
{{- $kubeletServiceOwner := tuple $envAll "kubelet" "kubelet.service" | include "kubeadm.fs.file_owner" -}}
{{- $kubeletDirMode := tuple $envAll "/var/lib/kubelet" | include "kubeadm.fs.dir_mode" -}}
{{- $kubeletDirOwner := tuple $envAll "/var/lib/kubelet" | include "kubeadm.fs.dir_owner" -}}
{{- $configYamlMode := tuple $envAll "kubelet" "config.yaml" | include "kubeadm.fs.file_mode" -}}
{{- $configYamlOwner := tuple $envAll "kubelet" "config.yaml" | include "kubeadm.fs.file_owner" -}}
# returns 0 if the files were changed, 1 if not
kubelet_sync_rc() {
  local c=1 # return code 1 means false

  kubelet_kubeconfig_sync_rc && c=0

  ensure_dir "${ROOTFS}/etc/default/" "{{ $defaultDirMode }}" "{{ $defaultDirOwner }}"
  subst_node_env "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet" | compare_copy_file - "${ROOTFS}/etc/default/kubelet" && c=0
  ensure_file "${ROOTFS}/etc/default/kubelet" "{{ $kubeletMode }}" "{{ $kubeletOwner }}"

  ensure_dir "${ROOTFS}/etc/systemd/system/" "{{ $systemdSystemDirMode }}" "{{ $systemdSystemDirOwner }}"
  compare_copy_file "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet.service" "${ROOTFS}/etc/systemd/system/kubelet.service" && c=0
  ensure_file "${ROOTFS}/etc/systemd/system/kubelet.service" "{{ $kubeletServiceMode }}" "{{ $kubeletServiceOwner }}"

  ensure_dir "${ROOTFS}/var/lib/kubelet/" "{{ $kubeletDirMode }}" "{{ $kubeletDirOwner }}"
  [ -f "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet_config.yaml" ] && compare_copy_file "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet_config.yaml" "${ROOTFS}/var/lib/kubelet/config.yaml" && c=0
  ensure_file "${ROOTFS}/var/lib/kubelet/config.yaml" "{{ $configYamlMode }}" "{{ $configYamlOwner }}"
  echo "kubelet is synced"
  return $c
}
{{- end -}}
{{- $_ := set $symbols "kubelet_sync_rc" (dict "needs" (list "kubelet_kubeconfig_sync_rc" "ensure_dir" "ensure_file" "subst_node_env" "compare_copy_file")
"body" (include "__kubelet_sync_rc" $envAll)
) -}}

{{/* the rebootstrap script only (templates/bin/_rebootstrap.tpl), the groups
     of kubelet_kubeconfig_sync_rc */}}
{{- $_ := set $symbols "kubelet_backup" (dict "needs" (list "group_dir_backup")
"body" `
# copies the certificates of kubelet of the node to the backup $1
kubelet_backup() {
  local pki_dir="/etc/kubernetes/pki"

  group_dir_backup "${ROOTFS}" "_kubeletpkipub" "${pki_dir}" "worker" "$1"
  group_dir_backup "${ROOTFS}" "_kubeletpkipriv" "${pki_dir}" "worker" "$1"
}
`) -}}

{{- $_ := set $symbols "kubelet_restore" (dict "needs" (list "group_dir_restore")
"body" `
# puts the certificates of kubelet of the backup $1 back
kubelet_restore() {
  local pki_dir="/etc/kubernetes/pki"

  group_dir_restore "${ROOTFS}" "_kubeletpkipub" "${pki_dir}" "worker" "$1"
  group_dir_restore "${ROOTFS}" "_kubeletpkipriv" "${pki_dir}" "worker" "$1"
}
`) -}}

{{- $_ := set $symbols "kubelet_start" (dict "body" `
kubelet_start() {
  systemctl daemon-reload
  systemctl enable kubelet
  systemctl restart kubelet
}
`) -}}

{{- $_ := set $symbols "kubelet_stop" (dict "body" `
kubelet_stop() {
  systemctl stop kubelet
}
`) -}}

{{- define "__kubelet_tls_bootstrap" -}}
{{- $envAll := . -}}
# the client certificate of kubelet from the new CA: kubelet goes through the
# TLS bootstrap again with the bootstrap token, as on the join (not kubeadm
# join phase kubelet-start: it refuses the node which is still Ready), it
# writes kubelet.conf, then the certificate once the CSR is approved,
# checks.attempts times 2 seconds apart
kubelet_tls_bootstrap() {
  local conf="${ROOTFS}/etc/kubernetes/bootstrap-kubelet.conf" n=1
  : "${KUBEADM_TOKEN:?the bootstrap token of the cluster}"
  rm -f "${ROOTFS}/etc/kubernetes/kubelet.conf" "${ROOTFS}"/var/lib/kubelet/pki/kubelet-client-*.pem
  kubectl config --kubeconfig "${conf}" set-cluster kubernetes \
    --server "https://{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}" \
    --certificate-authority "${ROOTFS}/etc/kubernetes/pki/kubelet-client-ca.pem" --embed-certs
  kubectl config --kubeconfig "${conf}" set-credentials tls-bootstrap-token-user --token "${KUBEADM_TOKEN}"
  kubectl config --kubeconfig "${conf}" set-context default --cluster kubernetes --user tls-bootstrap-token-user
  # kubectl writes it 0600
  kubectl config --kubeconfig "${conf}" use-context default
  systemctl daemon-reload
  systemctl restart kubelet
  until [ -f "${ROOTFS}/etc/kubernetes/kubelet.conf" ] && [ -f "${ROOTFS}/var/lib/kubelet/pki/kubelet-client-current.pem" ]; do
    if [ "$n" -ge {{ $envAll.Values.checks.attempts | int }} ]; then
      echo "kubelet didn't go through the TLS bootstrap" >&2
      return 1
    fi
    n=$((n + 1))
    sleep 2
  done
  rm -f "${conf}"
}
{{- end -}}
{{- $_ := set $symbols "kubelet_tls_bootstrap" (dict "body" (include "__kubelet_tls_bootstrap" $envAll)) -}}
