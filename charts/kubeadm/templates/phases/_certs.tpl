{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $controlPlaneNodes := get $k8sConfDict.fs "ctrl" -}}
{{- $perNode := get $k8sConfDict.fs "ctrl-pernode" -}}


{{/* steps were taken from https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/ certs part*/}}
{{- if $envAll.Values.certs -}}

  {{- if $envAll.Values.certs.ca -}}
    {{/* Populate pregenerated Kubernetes CA to provision identities for other Kubernetes components */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/ca.crt" (dict "content" $envAll.Values.certs.ca.crt "dest_path" "/etc/kubernetes/pki/ca.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_adminpkipub/cluster-ca.pem" (dict "content" $envAll.Values.certs.ca.crt "dest_path" "/etc/kubernetes/admin/pki/cluster-ca.pem" "file_mode" 0600 ) -}}
    {{- if $envAll.Values.certs.ca.key -}}
      {{- $_ := set $controlPlaneNodes "_pkipriv/ca.key" (dict "content" $envAll.Values.certs.ca.key "dest_path" "/etc/kubernetes/pki/ca.key" "file_mode" 0600 ) -}}
    {{- end -}}
  {{- end -}}

  {{- if $envAll.Values.certs.admin -}}
    {{- $_ := set $controlPlaneNodes "_adminpkipub/admin.pem" (dict "content" $envAll.Values.certs.admin.crt "dest_path" "/etc/kubernetes/admin/pki/admin.pem" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_adminpkipriv/admin-key.pem" (dict "content" $envAll.Values.certs.admin.key "dest_path" "/etc/kubernetes/admin/pki/admin-key.pem" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.scheduler -}}
    {{/* Populate pregenerated certificate for serving the Kubernetes API */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/scheduler.pem" (dict "content" $envAll.Values.certs.scheduler.crt "dest_path" "/etc/kubernetes/pki/scheduler.pem" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/scheduler-key.pem" (dict "content" $envAll.Values.certs.scheduler.key "dest_path" "/etc/kubernetes/pki/scheduler-key.pem" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.controller_manager -}}
    {{/* Populate pregenerated certificate for serving the Kubernetes API */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/controller-manager.pem" (dict "content" $envAll.Values.certs.controller_manager.crt "dest_path" "/etc/kubernetes/pki/controller-manager.pem" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/controller-manager-key.pem" (dict "content" $envAll.Values.certs.controller_manager.key "dest_path" "/etc/kubernetes/pki/controller-manager-key.pem" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.apiserver -}}
    {{/* Populate pregenerated certificate for serving the Kubernetes API */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/apiserver.crt" (dict "content" $envAll.Values.certs.apiserver.crt "dest_path" "/etc/kubernetes/pki/apiserver.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/apiserver.key" (dict "content" $envAll.Values.certs.apiserver.key "dest_path" "/etc/kubernetes/pki/apiserver.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.apiserver_kubelet_client -}}
    {{/* Populate pregenerated certificate for the API server to connect to kubelet */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/apiserver-kubelet-client.crt" (dict "content" $envAll.Values.certs.apiserver_kubelet_client.crt "dest_path" "/etc/kubernetes/pki/apiserver-kubelet-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/apiserver-kubelet-client.key" (dict "content" $envAll.Values.certs.apiserver_kubelet_client.key "dest_path" "/etc/kubernetes/pki/apiserver-kubelet-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.apiserver_etcd_client -}}
    {{/* Populate pregenerated certificate for the API server to connect to kubelet */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/apiserver-etcd-client.crt" (dict "content" $envAll.Values.certs.apiserver_etcd_client.crt "dest_path" "/etc/kubernetes/pki/apiserver-etcd-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/apiserver-etcd-client.key" (dict "content" $envAll.Values.certs.apiserver_etcd_client.key "dest_path" "/etc/kubernetes/pki/apiserver-etcd-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.front_proxy_ca -}}
    {{/* Populate pregenerated self-signed CA to provision identities for front proxy */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/front-proxy-ca.crt" (dict "content" $envAll.Values.certs.front_proxy_ca.crt "dest_path" "/etc/kubernetes/pki/front-proxy-ca.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/front-proxy-ca.key" (dict "content" $envAll.Values.certs.front_proxy_ca.key "dest_path" "/etc/kubernetes/pki/front-proxy-ca.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.front_proxy_client -}}
    {{/* Populate pregenerated certificate for the front proxy client */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/front-proxy-client.crt" (dict "content" $envAll.Values.certs.front_proxy_client.crt "dest_path" "/etc/kubernetes/pki/front-proxy-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/front-proxy-client.key" (dict "content" $envAll.Values.certs.front_proxy_client.key "dest_path" "/etc/kubernetes/pki/front-proxy-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.etcd_ca -}}
    {{/* Populate pregenerated self-signed CA to provision identities for etcd */}}
    {{- $_ := set $controlPlaneNodes "_etcdpub/ca.crt" (dict "content" $envAll.Values.certs.etcd_ca.crt "dest_path" "/etc/kubernetes/pki/etcd/ca.crt" "file_mode" 0600 ) -}}
    {{- if $envAll.Values.certs.etcd_ca.key -}}
      {{- $_ := set $controlPlaneNodes "_etcdpriv/ca.key" (dict "content" $envAll.Values.certs.etcd_ca.key "dest_path" "/etc/kubernetes/pki/etcd/ca.key" "file_mode" 0600 ) -}}
    {{- end -}}
  {{- end -}}
  {{- if $envAll.Values.certs.etcd_ca_peer -}}
    {{/* Populate pregenerated self-signed CA to provision identities for etcd (for peers) */}}
    {{- $_ := set $controlPlaneNodes "_etcdpub/ca-peer.crt" (dict "content" $envAll.Values.certs.etcd_ca_peer.crt "dest_path" "/etc/kubernetes/pki/etcd/ca-peer.crt" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.etcd_healthcheck_client -}}
    {{/* Populate pregenerated certificate for liveness probes to healthcheck etcd */}}
    {{- $_ := set $controlPlaneNodes "_etcdpub/healthcheck-client.crt" (dict "content" $envAll.Values.certs.etcd_healthcheck_client.crt "dest_path" "/etc/kubernetes/pki/etcd/healthcheck-client.crt" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_etcdpriv/healthcheck-client.key" (dict "content" $envAll.Values.certs.etcd_healthcheck_client.key  "dest_path" "/etc/kubernetes/pki/etcd/healthcheck-client.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- if $envAll.Values.certs.sa -}}
    {{/* Populate private key for signing service account tokens along with its public key */}}
    {{- $_ := set $controlPlaneNodes "_pkipub/sa.pub" (dict "content" $envAll.Values.certs.sa.pub "dest_path" "/etc/kubernetes/pki/sa.pub" "file_mode" 0600 ) -}}
    {{- $_ := set $controlPlaneNodes "_pkipriv/sa.key" (dict "content" $envAll.Values.certs.sa.key "dest_path" "/etc/kubernetes/pki/sa.key" "file_mode" 0600 ) -}}
  {{- end -}}

  {{- range $k,$v := $envAll.Values.certs.nodes -}}

    {{- $perNodeEntry := get $perNode $k | default (dict) -}}
    {{- $_ := set $perNode $k $perNodeEntry -}}
    {{/* Populate certificate for serving etcd */}}
    {{- if $v.etcd_server -}}
      {{- $_ := set $perNodeEntry "_etcdpub/server.crt" (dict "content" $v.etcd_server.crt "dest_path" "/etc/kubernetes/pki/etcd/server.crt" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "_etcdpriv/server.key" (dict "content" $v.etcd_server.key "dest_path" "/etc/kubernetes/pki/etcd/server.key" "file_mode" 0600) -}}
    {{- end -}}
    {{- if $v.etcd_peer -}}
      {{- $_ := set $perNodeEntry "_etcdpub/peer.crt" (dict "content" $v.etcd_peer.crt "dest_path" "/etc/kubernetes/pki/etcd/peer.crt" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "_etcdpriv/peer.key" (dict "content" $v.etcd_peer.key "dest_path" "/etc/kubernetes/pki/etcd/peer.key" "file_mode" 0600) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
  unpack pki and pki/etcd folders, ensuring correct rights.
*/}}
{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}
{{- $_ := set $sharedLibs $sharedLibName (printf `
sync_certs() {
  local pki_dir="/etc/kubernetes/pki"
  local etcd_dir="${pki_dir}/etcd"
  local admin_dir="/etc/kubernetes/admin/pki"

  ensure_dir "${ROOTFS}${pki_dir}" "%s" "%s"
  sync_group_dir "${ROOTFS}" "_pkipub" "${pki_dir}" "${NODE_ROLE}" false "%s" "%s"
  sync_group_dir "${ROOTFS}" "_pkipriv" "${pki_dir}" "${NODE_ROLE}" false "%s" "%s"
  if [ "${NODE_ROLE}" == "master" ]; then
    ensure_dir "${ROOTFS}${etcd_dir}" "%s" "%s"
    sync_group_dir "${ROOTFS}" "_etcdpub" "${etcd_dir}" "${NODE_ROLE}" false "%s" "%s"
    sync_group_dir "${ROOTFS}" "_etcdpriv" "${etcd_dir}" "${NODE_ROLE}" false "%s" "%s"

    ensure_dir "${ROOTFS}${admin_dir}" "%s" "%s"
    sync_group_dir "${ROOTFS}" "_adminpkipub" "${admin_dir}" "${NODE_ROLE}" false "%s" "%s"
    sync_group_dir "${ROOTFS}" "_adminpkipriv" "${admin_dir}" "${NODE_ROLE}" false "%s" "%s"

  fi
  echo "certs are synced"
}
`
(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipub") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipub") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipriv") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki" "pkipriv") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpub") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpub") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpriv") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/pki/etcd" "etcdpriv") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/admin/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/admin/pki") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/admin/pki" "adminpkipub") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/admin/pki" "adminpkipub") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/admin/pki" "adminpkipriv") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/admin/pki" "adminpkipriv") | include "kubeadm.bundle.template")

) -}}
{{- $_ := set $sharedLibs $sharedLibName (print (get $sharedLibs $sharedLibName) (include "__certs_ca_guard" $envAll)) -}}

{{/* ca_guard: called by the bootstrap and reconcile scripts before any sync */}}
{{- define "__certs_ca_guard" }}
# prints the public key of a certificate or a public key, the content if it is
# neither of them
public_key() {
  openssl x509 -noout -pubkey -in "$1" 2>/dev/null || openssl pkey -pubin -in "$1" 2>/dev/null || cat "$1"
}

# the CA and service account keys of the node sign its certificates and tokens:
# refuses to go on if the values deliver other ones. A CA certificate renewed
# with the same key is fine, CA rotation isn't supported.
guard_ca() {
  local src dst changed=""
  while read -r src dst; do
    [ -f "${ROOTFS}/run/kubeadm/${src}" ] && [ -f "${ROOTFS}${dst}" ] || continue
    if [ "$(public_key "${ROOTFS}/run/kubeadm/${src}")" != "$(public_key "${ROOTFS}${dst}")" ]; then
      case "${changed} " in
        *" ${dst} "*) ;;
        *) changed="${changed} ${dst}" ;;
      esac
    fi
  done << EOF_CA_GUARD
ctrl/_pkipub/ca.crt /etc/kubernetes/pki/ca.crt
all/_kubeletpkipub/kubelet-client-ca.pem /etc/kubernetes/pki/ca.crt
ctrl/_pkipub/front-proxy-ca.crt /etc/kubernetes/pki/front-proxy-ca.crt
ctrl/_etcdpub/ca.crt /etc/kubernetes/pki/etcd/ca.crt
ctrl/_pkipub/sa.pub /etc/kubernetes/pki/sa.pub
EOF_CA_GUARD
  if [ -n "${changed}" ]; then
    echo "ca_guard: the values deliver other keys than the ones of the node:${changed}" >&2
    echo "ca_guard: CA rotation isn't supported, revert certs in the values (or disable ca_guard)" >&2
    return 1
  fi
  echo "ca_guard: the keys of the node match the values"
}
{{ end }}
