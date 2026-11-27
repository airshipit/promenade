{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

#!define: reconcile
#!needs: KUBERNETES_DIR
#!needs: apiserver_files_sha256
#!needs: apiserver_restart
#!needs: apiserver_wait_ready
#!needs: binaries_sync_rc
#!needs: certs_sync
#!needs: cri_restart
#!needs: cri_sync_rc
#!needs: kubeadm_action
#!needs: kubeadm_action_required_rc
#!needs: kubeadm_cleanup_upgrade_backups
#!needs: kubeadm_mark_applied
#!needs: kubeadm_node_config
#!needs: kubeadm_sync
#!needs: kubeconfig_sync
#!needs: kubelet_mark_applied
#!needs: kubelet_restart_by_job
#!needs: kubelet_sync_rc
#!needs: node_info_field
#!needs: node_info_load
#!needs: node_info_update
#!needs: wait_apiservers_upgraded
#!needs: reconcile_wait_rebootstrap
# applies the chart to the node, upgrading Kubernetes on it when the version
# changes and repairing its control plane, then waits for the next change and
# returns, the anchor restarts with a new pass
reconcile() {
  local node_info
  local cri_restart_required=false
  local kubelet_restart_required=false
  local kubeadm_action_required=false
  local apiserver_files_before
  local tmp_dir rc
  local target_k8s_version={{ ($envAll.Values.cluster_config).kubernetesVersion | default "" | quote }}

  # waits while a rebootstrap is in progress
  reconcile_wait_rebootstrap

  # first, because the backups of failed passes may have filled the disk
  kubeadm_cleanup_upgrade_backups

{{- if $envAll.Values.anchor.reconcile.ca_guard }}
  # don't go further if the new CA is different, because the reconcile isn't
  # designed to change the CAs
  certs_ca_guard #!needs: certs_ca_guard
{{- end }}

  binaries_sync_rc kubeadm kubectl || true

  # read previously stored node state and annotations
  node_info=$(node_info_load)

  # the reconcile may run on a cluster bootstrapped by the previous Airship,
  # whose nodes have no configurations of the chart marked as applied. The
  # anchors of all such nodes may start together, so each one sleeps up to 30
  # seconds
  if [[ -z $(node_info_field "$node_info" kubeadm_applied) && -z $(node_info_field "$node_info" kubelet_applied) ]]; then
    sleep $(shuf -i 1-30 -n 1)
{{- if $envAll.Values.deprecated.airship_migration.enabled }}
    # MIGRATION from Airship. Marks the node for airship_migration_cleanup at
    # the end of the pass
    touch "${RECONCILE_DIR}/airship-migration"
{{- end }}
  fi

  # if it isn't specified - kubeadm uses the version which corresponds to the binary
  [ -n "$target_k8s_version" ] || target_k8s_version=$(kubeadm version -o short)
  # we won't be able to upgrade to the required version if kubeadm doesn't match
  if [[ $(kubeadm version -o short) != "$target_k8s_version" ]]; then
    echo "kubeadm $(kubeadm version -o short) on the node doesn't match kubernetesVersion $target_k8s_version, check binaries in values"
    exit 1
  fi

{{- if $envAll.Values.anchor.reconcile.os }}
  os_setup #!needs: os_setup
{{- end }}
{{- if $envAll.Values.anchor.reconcile.kube_cgroup }}
  kube_cgroup_setup #!needs: kube_cgroup_setup
{{- end }}

  # CRI update
{{- if $envAll.Values.anchor.reconcile.cri_install }}
  binary_cri_sync_rc && cri_restart_required={{ $envAll.Values.anchor.reconcile.cri_restart }} #!needs: binary_cri_sync_rc
{{- end }}

  cri_sync_rc && cri_restart_required={{ $envAll.Values.anchor.reconcile.cri_restart }}

  if [[ $cri_restart_required == true ]]; then
    cri_restart
  fi

  kubeconfig_sync

  # Kubelet update
  kubelet_sync_rc || true
  [ "${NODE_ROLE}" == "master" ] || wait_apiservers_upgraded "$target_k8s_version"
  binaries_sync_rc kubelet && kubelet_restart_required={{ $envAll.Values.anchor.reconcile.kubelet_restart }}

  # the apiserver restarts if the sync changed its files
  apiserver_files_before="$(apiserver_files_sha256)"

  certs_sync
  kubeadm_sync

  [ "$(apiserver_files_sha256)" == "${apiserver_files_before}" ] || apiserver_restart

  # the node runs etcd (the kubernetes-etcd label): kubeadm join and upgrade
  # must not skip its phases
  if [[ $(node_info_field "$node_info" etcd) == "enabled" ]]; then
    # do not skip etcd related phases
    [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
    # turn on etcd upgrade
    [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml" ] && sed "${SED_INPLACE[@]}" -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
  fi

  # the reconcile may run on a cluster bootstrapped by the previous Airship,
  # which kubeadm didn't create, so the ClusterConfiguration is uploaded and
  # cluster-info is created here
  if [ "${NODE_ROLE}" == "master" ] && [ -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]; then
    # kubeadm mutates the kubeconfig passed via --kubeconfig if it is a default one
    # (/etc/kubernetes/admin.conf). Operate on a throwaway copy of admin.conf so the
    # synced /etc/kubernetes/admin.conf on the host is not modified.
    tmp_dir="$(mktemp -d -p "${RECONCILE_DIR}")"
    cp "${ROOTFS}${KUBERNETES_DIR}/admin.conf" "${tmp_dir}/admin.conf"
    rc=0

    # kubeadm join and upgrade node take the ClusterConfiguration from the
    # kubeadm-config ConfigMap, this phase creates or updates it and
    # kubelet-config
    kubeadm_node_config > "${tmp_dir}/config.yaml"
    kubeadm init phase upload-config all --config "${tmp_dir}/config.yaml" --kubeconfig "${tmp_dir}/admin.conf" || rc=$?

    # kubeadm init creates cluster-info and the RBAC of the TLS bootstrap in its
    # bootstrap-token phase. They are missing on a cluster kubeadm didn't
    # create, e.g. taken over from Airship
    # (TODO) move this check prior to kubeadm join command, as well add a check if kubeconfig
    # has been modified due to cert rotation
    if [ $rc -eq 0 ] && ! kubectl get cm -n kube-public cluster-info; then
      kubeadm init phase bootstrap-token --kubeconfig "${tmp_dir}/admin.conf" || rc=$?
    fi

    rm -rf "${tmp_dir}"
    [ $rc -eq 0 ] || exit $rc
  fi


{{- if $envAll.Values.deprecated.airship_migration.enabled }}
  [ "${NODE_ROLE}" == "master" ] && rename_cp_pods #!needs: rename_cp_pods
{{- end }}

  # detecting if kubelet must be restarted
{{- if $envAll.Values.anchor.reconcile.kubelet_restart }}
  kubelet_restart_required_rc "$node_info" && kubelet_restart_required=true #!needs: kubelet_restart_required_rc

  # kubelet runs another version than the cluster, so its binary was upgraded
  [[ $(node_info_field "$node_info" kubelet_version) != $target_k8s_version ]] && kubelet_restart_required=true
{{- end }}

  # the anchor was restarted while the node was drained, e.g. because the new
  # kubelet restarted its containers. Restarting kubelet again uncordons the
  # node
  [[ -n $(node_info_field "$node_info" kubelet_restarting) ]] && kubelet_restart_required=true

  kubeadm_action_required_rc "$node_info" && kubeadm_action_required=true
  if [[ $kubeadm_action_required == true ]]; then
    kubeadm_action "$node_info"
    # kubeadm join or upgrade recreates the static pods of the control plane
    apiserver_wait_ready
    kubeadm_mark_applied
    node_info=$(node_info_load)
  fi

  if [[ $kubelet_restart_required == true ]]; then
    kubelet_restart_by_job
    kubelet_mark_applied
    node_info=$(node_info_load)
  fi

{{- if $envAll.Values.deprecated.airship_migration.enabled }}
  airship_migration_cleanup #!needs: airship_migration_cleanup
{{- end }}

{{- if $envAll.Values.anchor.reconcile.checks }}
  # the anchor becomes ready only if the node checks pass
  check_run{{ if $envAll.Values.anchor.reconcile.vip }} vip_check{{ end }} certs_check #!needs: check_run, certs_check{{ if $envAll.Values.anchor.reconcile.vip }}, vip_check{{ end }}
{{- end }}

  # the anchor is ready
  touch "${RECONCILE_DIR}/ready"

  # main loop
  while true; do
    if [ -e "${RECONCILE_DIR}/stop" ] || kubeadm_action_required_rc "$node_info" \
{{- if $envAll.Values.anchor.reconcile.kubelet_restart }}
      || kubelet_restart_required_rc "$node_info" \
      || [[ $(node_info_field "$node_info" kubelet_version) != $target_k8s_version ]] \
{{- end }}
      ; then
      echo "Stopping"
      break
    fi
{{- if $envAll.Values.anchor.reconcile.vip }}
    # the VIP the node was bootstrapped with follows the control plane endpoints
    vip_reconcile || true #!needs: vip_reconcile
{{- end }}
    sleep {{ $envAll.Values.anchor.reconcile.period }}
  done
}
