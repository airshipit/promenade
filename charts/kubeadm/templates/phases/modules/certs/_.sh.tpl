{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $controlPlaneNodes := get (get $k8sConfDict "fs") "ctrl" -}}
{{- $perNode := get (get $k8sConfDict "fs") "ctrl-pernode" -}}

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
    {{/* Populate certificate for serving the Kubernetes API of the node (the
         SANs of the node, as kubeadm issues it), instead of certs.apiserver
         shared by all the control plane nodes */}}
    {{- if $v.apiserver -}}
      {{- $_ := set $perNodeEntry "_pkipub/apiserver.crt" (dict "content" $v.apiserver.crt "dest_path" "/etc/kubernetes/pki/apiserver.crt" "file_mode" 0600) -}}
      {{- $_ := set $perNodeEntry "_pkipriv/apiserver.key" (dict "content" $v.apiserver.key "dest_path" "/etc/kubernetes/pki/apiserver.key" "file_mode" 0600) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

#!define: certs_sync
#!needs: ensure_dir, group_dir_sync
{{- $kubernetesPkiDirMode := tuple $envAll "/etc/kubernetes/pki" | include "kubeadm.fs.dir_mode" }}
{{- $kubernetesPkiDirOwner := tuple $envAll "/etc/kubernetes/pki" | include "kubeadm.fs.dir_owner" }}
{{- $pkipubMode := tuple $envAll "certs" "pkipub" | include "kubeadm.fs.file_mode" }}
{{- $pkipubOwner := tuple $envAll "certs" "pkipub" | include "kubeadm.fs.file_owner" }}
{{- $pkiprivMode := tuple $envAll "certs" "pkipriv" | include "kubeadm.fs.file_mode" }}
{{- $pkiprivOwner := tuple $envAll "certs" "pkipriv" | include "kubeadm.fs.file_owner" }}
{{- $kubernetesPkiEtcdDirMode := tuple $envAll "/etc/kubernetes/pki/etcd" | include "kubeadm.fs.dir_mode" }}
{{- $kubernetesPkiEtcdDirOwner := tuple $envAll "/etc/kubernetes/pki/etcd" | include "kubeadm.fs.dir_owner" }}
{{- $etcdpubMode := tuple $envAll "certs" "etcdpub" | include "kubeadm.fs.file_mode" }}
{{- $etcdpubOwner := tuple $envAll "certs" "etcdpub" | include "kubeadm.fs.file_owner" }}
{{- $etcdprivMode := tuple $envAll "certs" "etcdpriv" | include "kubeadm.fs.file_mode" }}
{{- $etcdprivOwner := tuple $envAll "certs" "etcdpriv" | include "kubeadm.fs.file_owner" }}
{{- $kubernetesAdminPkiDirMode := tuple $envAll "/etc/kubernetes/admin/pki" | include "kubeadm.fs.dir_mode" }}
{{- $kubernetesAdminPkiDirOwner := tuple $envAll "/etc/kubernetes/admin/pki" | include "kubeadm.fs.dir_owner" }}
{{- $adminpkipubMode := tuple $envAll "certs" "adminpkipub" | include "kubeadm.fs.file_mode" }}
{{- $adminpkipubOwner := tuple $envAll "certs" "adminpkipub" | include "kubeadm.fs.file_owner" }}
{{- $adminpkiprivMode := tuple $envAll "certs" "adminpkipriv" | include "kubeadm.fs.file_mode" }}
{{- $adminpkiprivOwner := tuple $envAll "certs" "adminpkipriv" | include "kubeadm.fs.file_owner" }}
certs_sync() {
  local pki_dir="/etc/kubernetes/pki"
  local etcd_dir="${pki_dir}/etcd"
  local admin_dir="/etc/kubernetes/admin/pki"

  ensure_dir "${ROOTFS}${pki_dir}" "{{ $kubernetesPkiDirMode }}" "{{ $kubernetesPkiDirOwner }}"
  group_dir_sync "${ROOTFS}" "_pkipub" "${pki_dir}" "${NODE_ROLE}" false "{{ $pkipubMode }}" "{{ $pkipubOwner }}"
  group_dir_sync "${ROOTFS}" "_pkipriv" "${pki_dir}" "${NODE_ROLE}" false "{{ $pkiprivMode }}" "{{ $pkiprivOwner }}"
  if [ "${NODE_ROLE}" == "master" ]; then
    ensure_dir "${ROOTFS}${etcd_dir}" "{{ $kubernetesPkiEtcdDirMode }}" "{{ $kubernetesPkiEtcdDirOwner }}"
    group_dir_sync "${ROOTFS}" "_etcdpub" "${etcd_dir}" "${NODE_ROLE}" false "{{ $etcdpubMode }}" "{{ $etcdpubOwner }}"
    group_dir_sync "${ROOTFS}" "_etcdpriv" "${etcd_dir}" "${NODE_ROLE}" false "{{ $etcdprivMode }}" "{{ $etcdprivOwner }}"

    ensure_dir "${ROOTFS}${admin_dir}" "{{ $kubernetesAdminPkiDirMode }}" "{{ $kubernetesAdminPkiDirOwner }}"
    group_dir_sync "${ROOTFS}" "_adminpkipub" "${admin_dir}" "${NODE_ROLE}" false "{{ $adminpkipubMode }}" "{{ $adminpkipubOwner }}"
    group_dir_sync "${ROOTFS}" "_adminpkipriv" "${admin_dir}" "${NODE_ROLE}" false "{{ $adminpkiprivMode }}" "{{ $adminpkiprivOwner }}"

  fi
  echo "certs are synced"
}

#!define: certs_backup
#!needs: group_dir_backup
# copies the certificates of the node to the backup $1
certs_backup() {
  local pki_dir="/etc/kubernetes/pki"
  local etcd_dir="${pki_dir}/etcd"
  local admin_dir="/etc/kubernetes/admin/pki"

  group_dir_backup "${ROOTFS}" "_pkipub" "${pki_dir}" "${NODE_ROLE}" "$1"
  group_dir_backup "${ROOTFS}" "_pkipriv" "${pki_dir}" "${NODE_ROLE}" "$1"
  if [ "${NODE_ROLE}" == "master" ]; then
    group_dir_backup "${ROOTFS}" "_etcdpub" "${etcd_dir}" "${NODE_ROLE}" "$1"
    group_dir_backup "${ROOTFS}" "_etcdpriv" "${etcd_dir}" "${NODE_ROLE}" "$1"
    group_dir_backup "${ROOTFS}" "_adminpkipub" "${admin_dir}" "${NODE_ROLE}" "$1"
    group_dir_backup "${ROOTFS}" "_adminpkipriv" "${admin_dir}" "${NODE_ROLE}" "$1"
  fi
}

#!define: certs_restore
#!needs: group_dir_restore
# puts the certificates of the backup $1 back
certs_restore() {
  local pki_dir="/etc/kubernetes/pki"
  local etcd_dir="${pki_dir}/etcd"
  local admin_dir="/etc/kubernetes/admin/pki"

  group_dir_restore "${ROOTFS}" "_pkipub" "${pki_dir}" "${NODE_ROLE}" "$1"
  group_dir_restore "${ROOTFS}" "_pkipriv" "${pki_dir}" "${NODE_ROLE}" "$1"
  if [ "${NODE_ROLE}" == "master" ]; then
    group_dir_restore "${ROOTFS}" "_etcdpub" "${etcd_dir}" "${NODE_ROLE}" "$1"
    group_dir_restore "${ROOTFS}" "_etcdpriv" "${etcd_dir}" "${NODE_ROLE}" "$1"
    group_dir_restore "${ROOTFS}" "_adminpkipub" "${admin_dir}" "${NODE_ROLE}" "$1"
    group_dir_restore "${ROOTFS}" "_adminpkipriv" "${admin_dir}" "${NODE_ROLE}" "$1"
  fi
}

#!define: certs_generate_with_kubeadm
#!needs: kubeadm_generated_files, kubeadm_node_config, kubelet_kubeconfig_sync_rc, kubelet_tls_bootstrap

# certs_generate_with_kubeadm's helper: the certificates and the kubeconfigs
# kubeadm generated from the old CAs, the client certificates of kubelet (it
# would take the current one): kubeadm generates them from the new CAs, as
# kubeadm init did
_kubeadm_init_certs() {
  local file dir super_admin=false
  # kubeadm init generates it on the first control plane node only
  [ -f "${ROOTFS}/etc/kubernetes/super-admin.conf" ] && super_admin=true
  for file in $(kubeadm_generated_files); do
    rm -f "${ROOTFS}${file}"
  done
  rm -f "${ROOTFS}"/var/lib/kubelet/pki/kubelet-client-*.pem
  dir=$(mktemp -d)
  kubeadm_node_config > "${dir}/config.yaml"
  kubeadm init phase certs all --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig admin --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig controller-manager --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig scheduler --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig kubelet --config "${dir}/config.yaml"
  if [ "${super_admin}" == "true" ]; then
    kubeadm init phase kubeconfig super-admin --config "${dir}/config.yaml"
  fi
  rm -rf "${dir}"
  # kubelet goes through the control plane endpoint
  kubelet_kubeconfig_sync_rc || true
}

# what kubeadm generated from the old CAs on the node, from the new ones
certs_generate_with_kubeadm() {
  if [ "${NODE_ROLE}" == "master" ]; then
    _kubeadm_init_certs
  else
    kubelet_tls_bootstrap
  fi
}

#!define: certs_guard_ca
{{- /* certs_guard_ca: called by the bootstrap and reconcile scripts before any sync */}}

# certs_guard_ca's helper: prints the public key of a certificate or a public
# key, the content if it is neither of them
_public_key() {
  openssl x509 -noout -pubkey -in "$1" 2>/dev/null || openssl pkey -pubin -in "$1" 2>/dev/null || cat "$1"
}

# the CA and service account keys of the node sign its certificates and tokens:
# refuses to go on if the values deliver other ones. A CA certificate renewed
# with the same key is fine, CA rotation isn't supported.
certs_guard_ca() {
  local src dst changed=""
  while read -r src dst; do
    [ -f "${ROOTFS}/run/kubeadm/${src}" ] && [ -f "${ROOTFS}${dst}" ] || continue
    if [ "$(_public_key "${ROOTFS}/run/kubeadm/${src}")" != "$(_public_key "${ROOTFS}${dst}")" ]; then
      case "${changed} " in
        *" ${dst} "*) ;;
        *) changed="${changed} ${dst}" ;;
      esac
    fi
  done << EOF_CA_GUARD
ctrl/_pkipub/ca.crt /etc/kubernetes/pki/ca.crt
all/_kubeletpkipub/kubelet-client-ca.pem /etc/kubernetes/pki/kubelet-client-ca.pem
ctrl/_pkipub/front-proxy-ca.crt /etc/kubernetes/pki/front-proxy-ca.crt
ctrl/_etcdpub/ca.crt /etc/kubernetes/pki/etcd/ca.crt
ctrl/_pkipub/sa.pub /etc/kubernetes/pki/sa.pub
EOF_CA_GUARD
  if [ -n "${changed}" ]; then
    echo "certs_guard_ca: the values deliver other keys than the ones of the node:${changed}" >&2
    echo "certs_guard_ca: the CAs are rotated by the rebootstrap, revert certs in the values" >&2
    return 1
  fi
  echo "certs_guard_ca: the keys of the node match the values"
}

#!define: certs_check
#!needs: check_attempts, check_result, static_pod_flag
{{- /* certs_check: called by the reconcile script before the anchor becomes ready */}}

# certs_check's helper: the server $1 (host:port) serves the certificate file
# $2, it has reloaded it
_certs_served_rc() {
  local served file
  # the server may refuse the handshake without a client certificate, its
  # certificate is printed anyway
  served=$(openssl s_client -connect "$1" < /dev/null 2> /dev/null | openssl x509 -noout -fingerprint -sha256) || true
  file=$(openssl x509 -noout -fingerprint -sha256 -in "${ROOTFS}$2")
  [ -n "${served}" ] && [ "${served}" = "${file}" ]
}

# the components of the node serve the certificates of its files: they reload
# them after the sync, the anchor becomes ready once they did. The endpoints
# and the certificates are the ones the components run with: the apiserver and
# etcd if the node runs them (their manifests), kubelet (its configuration)
certs_check() {
  local apiserver=/etc/kubernetes/manifests/kube-apiserver.yaml
  local etcd=/etc/kubernetes/manifests/etcd.yaml
  local kubelet="${ROOTFS}/var/lib/kubelet/config.yaml"
  local etcd_url kubelet_port kubelet_crt endpoint file
  # the first client url of etcd, kubeadm puts 127.0.0.1 first
  etcd_url=$(static_pod_flag "${etcd}" listen-client-urls)
  etcd_url="${etcd_url%%,*}"
  # 10250 is the default port of kubelet
  kubelet_port=$(sed -n 's/^port: *//p' "${kubelet}")
  kubelet_crt=$(sed -n 's/^tlsCertFile: *//p' "${kubelet}" | tr -d '"')
  while read -r endpoint file; do
    # the node doesn't run the component or it has no certificate of the files
    [ -n "${file}" ] || continue
    if check_attempts _certs_served_rc "${endpoint}" "${file}"; then
      check_result OK certs "${endpoint} serves ${file}"
    else
      check_result FAIL certs "${endpoint} doesn't serve ${file}"
    fi
  done << EOF_CERTS_CHECK
127.0.0.1:$(static_pod_flag "${apiserver}" secure-port) $(static_pod_flag "${apiserver}" tls-cert-file)
${etcd_url#*://} $(static_pod_flag "${etcd}" cert-file)
127.0.0.1:${kubelet_port:-10250} ${kubelet_crt}
EOF_CERTS_CHECK
  return 0
}

#!define: certs_refresh_clients

# certs_refresh_clients's helper: the new CA in kube-root-ca.crt of all the
# namespaces (the controller-manager publishes it): the pods started before it
# get the old one and keep it
_wait_root_ca() {
  local kubectl=(kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/admin.conf")
  local ca namespaces ns stale="" i
  ca=$(cat "${ROOTFS}/etc/kubernetes/pki/ca.crt") || return 1
  for i in $(seq 60); do
    if namespaces=$("${kubectl[@]}" get namespaces -o name) && [ -n "${namespaces}" ]; then
      stale=""
      for ns in ${namespaces}; do
        ns="${ns#namespace/}"
        [ "$("${kubectl[@]}" -n "${ns}" get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')" = "${ca}" ] ||
          stale="${stale} ${ns}"
      done
      [ -n "${stale}" ] || return 0
    fi
    sleep 2
  done
  echo "kube-root-ca.crt without the new CA:${stale:- (no namespaces)}" >&2
  return 1
}

# certs_refresh_clients's helper: the pods of the selector, the API of the
# restarted control plane may be unavailable for a while
_delete_pods() {
  local kubectl=(kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/admin.conf")
  local delay
  for delay in 0 1 2 4 8; do
    sleep "${delay}"
    "${kubectl[@]}" delete pods --all-namespaces -l "$1" --grace-period=0 --force && return 0
  done
  return 1
}

# the abrupt rotation: the pods keep the CA (kube-root-ca.crt) and the service
# account tokens they started with, they don't work anyway, their controllers
# start them again once the new CA is published
certs_refresh_clients() {
  _wait_root_ca || return 1
{{- range $selector := $envAll.Values.certs.refresh_clients_selectors }}
  _delete_pods {{ $selector | quote }}
{{- end }}
  return 0
}
