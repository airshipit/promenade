{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

#!define: etcd_restore
#!needs: binaries_sync_rc, binary_etcd_sync_rc, kubeadm_node_config, static_pod_flag
# restores the etcd snapshot file $1 to the data dir of etcd on the first
# control plane node before kubeadm init starts etcd on it. The member name,
# the peer URL and the data dir come from the etcd manifest of
# kubeadm init --dry-run, so they match the manifest kubeadm writes later.
# NOTE: The data dir isn't empty so kubeadm init needs
# --ignore-preflight-errors=DirAvailable--var-lib-etcd
etcd_restore() {
  local snapshot="$1" dir manifest name peer data_dir
  binary_etcd_sync_rc || true
  binaries_sync_rc kubeadm || true
  dir=$(mktemp -d "${ROOTFS}/tmp/etcd-restore.XXXXXX")
  kubeadm_node_config > "${dir}/config.yaml"
  KUBEADM_INIT_DRYRUN_DIR="${dir}" kubeadm init phase etcd local --config "${dir}/config.yaml" --dry-run
  manifest="${dir#"${ROOTFS}"}/etcd.yaml"
  name=$(static_pod_flag "${manifest}" name)
  peer=$(static_pod_flag "${manifest}" initial-advertise-peer-urls)
  data_dir=$(static_pod_flag "${manifest}" data-dir)
  rm -rf "${dir}"
  if [ -z "${name}" ] || [ -z "${peer}" ] || [ -z "${data_dir}" ]; then
    echo "etcd_restore: no --name, --initial-advertise-peer-urls or --data-dir in the etcd manifest of kubeadm init --dry-run" >&2
    exit 1
  fi
  # kubeadm reset leaves the data dir empty, etcdutl refuses an existing one
  rmdir "${ROOTFS}${data_dir}" 2> /dev/null || true
  etcdutl snapshot restore "${snapshot}" --data-dir "${ROOTFS}${data_dir}" --name "${name}" \
    --initial-cluster "${name}=${peer}" --initial-advertise-peer-urls "${peer}"
}
