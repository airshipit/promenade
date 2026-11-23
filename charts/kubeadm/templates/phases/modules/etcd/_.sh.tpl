{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

#!define: etcd_restore
#!needs: binary_etcd_sync_rc, kubeadm_node_config
# the stacked etcd of the first control plane node from the snapshot $1 (a
# file on the node), before kubeadm init: kubeadm starts etcd with the data dir
# it finds there. The member gets the name and the peer URL kubeadm gives it
# (the node name and the advertise address of its configuration), the other
# control plane nodes join it as usual. kubeadm init needs
# --ignore-preflight-errors=DirAvailable--var-lib-etcd then
etcd_restore() {
  local snapshot="$1" config name ip dir
  binary_etcd_sync_rc || true
  config=$(kubeadm_node_config)
  name=$(sed -n '/^nodeRegistration:/,/^[^ ]/s/^  name: *//p' <<< "${config}" | tr -d '"')
  ip=$(sed -n '/^localAPIEndpoint:/,/^[^ ]/s/^  advertiseAddress: *//p' <<< "${config}" | tr -d '"')
  dir=$(sed -n '/^etcd:/,/^[^ ]/s/^    dataDir: *//p' <<< "${config}" | tr -d '"')
  if [ -z "${name}" ] || [ -z "${ip}" ]; then
    echo "etcd_restore: the configuration of the node has no nodeRegistration.name or localAPIEndpoint.advertiseAddress" >&2
    exit 1
  fi
  [[ "${ip}" != *:* ]] || ip="[${ip}]"
  dir="${ROOTFS}${dir:-/var/lib/etcd}"
  # kubeadm reset leaves the data dir empty, etcdutl refuses an existing one
  rmdir "${dir}" 2> /dev/null || true
  etcdutl snapshot restore "${snapshot}" --data-dir "${dir}" --name "${name}" \
    --initial-cluster "${name}=https://${ip}:2380" \
    --initial-advertise-peer-urls "https://${ip}:2380"
}
