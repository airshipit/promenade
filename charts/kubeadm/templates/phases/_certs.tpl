{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict "allNodes" -}}
{{- $controlPlaneNodes := get $k8sConfDict "controlPlaneNodes" -}}
{{- $perNode := get $k8sConfDict "perNode" -}}


{{/* steps were taken from https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/ certs part*/}}
{{- if $envAll.Values.certs -}}

  {{- if $envAll.Values.certs.ca -}}
    {{/* Populate pregenerated Kubernetes CA to provision identities for other Kubernetes components */}}
    {{- $_ := set $controlPlaneNodes "pkipub_ca.crt" (dict "content" $envAll.Values.certs.ca.crt "dest_path" "/etc/kubernetes/pki/ca.crt" "file_mode" 0600 ) -}}
    {{- if $envAll.Values.certs.ca.key -}}
      {{- $_ := set $controlPlaneNodes "pkipriv_ca.key" (dict "content" $envAll.Values.certs.ca.key "dest_path" "/etc/kubernetes/pki/ca.key" "file_mode" 0600 ) -}}
    {{- end -}}
  {{- end -}}

  {{- if $envAll.Values.certs.scheduler -}}
    {{/* Populate pregenerated certificate for serving the Kubernetes API */}}
    {{- $_ := set $controlPlaneNodes "pkipub_scheduler.pem" (dict "content" $envAll.Values.certs.scheduler.crt "dest_path" "/etc/kubernetes/pki/sscheduler.pem" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_scheduler-key.pem" (dict "content" $envAll.Values.certs.scheduler.key "dest_path" "/etc/kubernetes/pki/scheduler-key.pem" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.controller_manager -}}
    {{/* Populate pregenerated certificate for serving the Kubernetes API */}}
    {{- $_ := set $controlPlaneNodes "pkipub_controller-manager.pem" (dict "content" $envAll.Values.certs.controller_manager.crt "dest_path" "/etc/kubernetes/pki/controller-manager.pem" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_controller-manager-key.pem" (dict "content" $envAll.Values.certs.controller_manager.key "dest_path" "/etc/kubernetes/pki/controller-manager-key.pem" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.apiserver -}}
    {{/* Populate pregenerated certificate for serving the Kubernetes API */}}
    {{- $_ := set $controlPlaneNodes "pkipub_apiserver.crt" (dict "content" $envAll.Values.certs.apiserver.crt "dest_path" "/etc/kubernetes/pki/apiserver.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_apiserver.key" (dict "content" $envAll.Values.certs.apiserver.key "dest_path" "/etc/kubernetes/pki/apiserver.key" "file_mode" 0600 ) -}}
  {{- end -}}


  {{- if $envAll.Values.certs.apiserver_kubelet_client -}}
    {{/* Populate pregenerated certificate for the API server to connect to kubelet */}}
    {{- $_ := set $controlPlaneNodes "pkipub_apiserver-kubelet-client.crt" (dict "content" $envAll.Values.certs.apiserver_kubelet_client.crt "dest_path" "/etc/kubernetes/pki/apiserver-kubelet-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_apiserver-kubelet-client.key" (dict "content" $envAll.Values.certs.apiserver_kubelet_client.key "dest_path" "/etc/kubernetes/pki/apiserver-kubelet-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.apiserver_etcd_client -}}
    {{/* Populate pregenerated certificate for the API server to connect to kubelet */}}
    {{- $_ := set $controlPlaneNodes "pkipub_apiserver-etcd-client.crt" (dict "content" $envAll.Values.certs.apiserver_etcd_client.crt "dest_path" "/etc/kubernetes/pki/apiserver-etcd-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_apiserver-etcd-client.key" (dict "content" $envAll.Values.certs.apiserver_etcd_client.key "dest_path" "/etc/kubernetes/pki/apiserver-etcd-client.key" "file_mode" 0600 ) -}}
  {{- end -}}


  {{- if $envAll.Values.certs.front_proxy_ca -}}
    {{/* Populate pregenerated self-signed CA to provision identities for front proxy */}}
    {{- $_ := set $controlPlaneNodes "pkipub_front-proxy-ca.crt" (dict "content" $envAll.Values.certs.front_proxy_ca.crt "dest_path" "/etc/kubernetes/pki/front-proxy-ca.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_front-proxy-ca.key" (dict "content" $envAll.Values.certs.front_proxy_ca.key "dest_path" "/etc/kubernetes/pki/front-proxy-ca.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.front_proxy_client -}}
    {{/* Populate pregenerated certificate for the front proxy client */}}
    {{- $_ := set $controlPlaneNodes "pkipub_front-proxy-client.crt" (dict "content" $envAll.Values.certs.front_proxy_client.crt "dest_path" "/etc/kubernetes/pki/front-proxy-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_front-proxy-client.key" (dict "content" $envAll.Values.certs.front_proxy_client.key "dest_path" "/etc/kubernetes/pki/front-proxy-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.etcd_ca -}}
    {{/* Populate pregenerated self-signed CA to provision identities for etcd */}}
    {{- $_ := set $controlPlaneNodes "etcdpub_ca.crt" (dict "content" $envAll.Values.certs.etcd_ca.crt "dest_path" "/etc/kubernetes/pki/etcd/ca.crt" "file_mode" 0600 ) -}}
  {{- end -}}
  {{- if $envAll.Values.certs.etcd_ca_peer -}}
    {{/* Populate pregenerated self-signed CA to provision identities for etcd (for peers) */}}
    {{- $_ := set $controlPlaneNodes "etcdpub_ca-peer.crt" (dict "content" $envAll.Values.certs.etcd_ca_peer.crt "dest_path" "/etc/kubernetes/pki/etcd/ca-peer.crt" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.etcd_healthcheck_client -}}
    {{/* Populate pregenerated certificate for liveness probes to healthcheck etcd */}}
    {{- $_ := set $controlPlaneNodes "etcdpub_healthcheck-client.crt" (dict "content" $envAll.Values.certs.etcd_healthcheck_client.crt "dest_path" "/etc/kubernetes/pki/etcd/healthcheck-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "etcdpriv_healthcheck-client.key" (dict "content" $envAll.Values.certs.etcd_healthcheck_client.key  "dest_path" "/etc/kubernetes/pki/etcd/healthcheck-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.apiserver_kubelet_client -}}
    {{/* Populate pregenerated certificate for the API server to connect to kubelet */}}
    {{- $_ := set $controlPlaneNodes "pkipub_apiserver-kubelet-client.crt" (dict "content" $envAll.Values.certs.apiserver_kubelet_client.crt "dest_path" "/etc/kubernetes/pki/apiserver-kubelet-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_apiserver-kubelet-client.key" (dict "content" $envAll.Values.certs.apiserver_kubelet_client.key "dest_path" "/etc/kubernetes/pki/apiserver-kubelet-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.sa -}}
    {{/* Populate private key for signing service account tokens along with its public key */}}
    {{- $_ := set $controlPlaneNodes "pkipub_sa.pub" (dict "content" $envAll.Values.certs.sa.pub "dest_path" "/etc/kubernetes/pki/sa.pub" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "pkipriv_sa.key" (dict "content" $envAll.Values.certs.sa.key "dest_path" "/etc/kubernetes/pki/sa.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- range $k,$v := $envAll.Values.certs.nodes -}}

    {{- $perNodeEntry := get $perNode $k | default (dict) -}}
    {{- $_ := set $perNode $k $perNodeEntry -}}
    {{/* Populate certificate for serving etcd */}}
    {{- if $v.etcd_server -}}
      {{- $_ := set $perNodeEntry "etcdpub_server.crt" (dict "content" $v.etcd_server.crt "dest_path" "/etc/kubernetes/pki/etcd/server.crt" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "etcdpriv_server.key" (dict "content" $v.etcd_server.key "dest_path" "/etc/kubernetes/pki/etcd/server.key" "file_mode" 0600) -}}
    {{- end -}}
    {{- if $v.etcd_peer -}}
      {{- $_ := set $perNodeEntry "etcdpub_peer.crt" (dict "content" $v.etcd_peer.crt "dest_path" "/etc/kubernetes/pki/etcd/peer.crt" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "etcdpriv_peer.key" (dict "content" $v.etcd_peer.key "dest_path" "/etc/kubernetes/pki/etcd/peer.key" "file_mode" 0600) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
  unpack pki and pki/etcd folders, ensuring correct rights.
*/}}
{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}
{{- $_ := set $sharedLibs $sharedLibName (printf `
sync_certs() {
  local pki_dir="${HOST_DIR}/etc/kubernetes/pki"
  local etcd_dir="${pki_dir}/etcd"

  ensure_dir "${ROOTFS}${pki_dir}" "%s" "%s"
  sync_prefix_based_dir "${ROOTFS}" "${pki_dir}" "pkipub_" "${NODE_ROLE}" false "%s" "%s"
  sync_prefix_based_dir "${ROOTFS}" "${pki_dir}" "pkipriv_" "${NODE_ROLE}" false "%s" "%s"
  if [ "${NODE_ROLE}" == "master" ]; then
    ensure_dir "${ROOTFS}${etcd_dir}" "%s" "%s"
    sync_prefix_based_dir "${ROOTFS}" "${etcd_dir}" "etcdpub_" "${NODE_ROLE}" false "%s" "%s"
    sync_prefix_based_dir "${ROOTFS}" "${etcd_dir}" "etcdpriv_" "${NODE_ROLE}" false "%s" "%s"
  fi
  echo "certs are synced"
}
`
(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipub_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipub_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipriv_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipriv_") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpub_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpub_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpriv_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpriv_") | include "kubeadm.bundle.template")
) -}}