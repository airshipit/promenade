{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

#!define: reconcile
#!needs: KUBERNETES_DIR
#!needs: apiserver_files_sha256
#!needs: apiserver_restart
#!needs: binaries_sync_rc
#!needs: certs_sync
#!needs: cri_restart
#!needs: cri_sync_rc
#!needs: kubeadm_action
#!needs: kubeadm_action_required_rc
#!needs: kubeadm_mark_applied
#!needs: kubeadm_node_config
#!needs: kubeadm_sync
#!needs: kubeadm_upgrade_backups_cleanup
#!needs: kubeconfig_sync
#!needs: kubelet_mark_applied
#!needs: kubelet_restart_by_job
#!needs: kubelet_sync_rc
#!needs: node_info_field
#!needs: node_info_load
#!needs: node_info_update
#!needs: wait_apiservers_upgraded
#!needs: wait_rebootstrap
# one pass (the state of the node, the files of the chart synced, the changes
# applied: kubeadm, the restart of kubelet, the node checks), the anchor is
# ready, then the main loop: a change needing a new pass ends it (the anchor
# restarts), the VIP the node was bootstrapped with follows the control plane
# endpoints meanwhile
reconcile() {
  local node_info
  local cri_restart_required=false
  local kubelet_restart_required=false
  local kubeadm_action_required=false
  local apiserver_files_before
  local tmp_dir rc
  local target_k8s_version={{ ($envAll.Values.cluster_config).kubernetesVersion | default "" | quote }}

  # gate - don't go until rebootstrap is working
  wait_rebootstrap

  # first: the backups of failed passes may have filled the disk
  kubeadm_upgrade_backups_cleanup

{{- if $envAll.Values.anchor.reconcile.ca_guard }}
  # before any sync: the files of the node are left as they are
  certs_guard_ca #!needs: certs_guard_ca
{{- end }}

  binaries_sync_rc kubeadm kubectl || true

  # read previously stored node state and annotations
  node_info=$(node_info_load)

  # no trace of the bootstrap or of a reconcile (e.g. a cluster taken over from
  # Airship): the anchors of all the nodes may start together, sleep randomly up
  # to 30 seconds
  if [[ -z $(node_info_field "$node_info" kubeadm_applied) && -z $(node_info_field "$node_info" kubelet_applied) ]]; then
    sleep $(shuf -i 1-30 -n 1)
{{- if $envAll.Values.deprecated.airship_migration.enabled }}
    # MIGRATION from Airship: a node without the annotations of the chart (any
    # role), its files are removed at the end of the pass
    touch "${RECONCILE_DIR}/airship-migration"
{{- end }}
  fi

  # if isn't specified - kubeadm uses the version which corresponds to the binary
  [ -n "$target_k8s_version" ] || target_k8s_version=$(kubeadm version -o short)
  # we won't be able to upgrade to the required version if kubeadm doesn't match
  if [[ $(kubeadm version -o short) != "$target_k8s_version" ]]; then
    echo "kubeadm $(kubeadm version -o short) on the node doesn't match kubernetesVersion $target_k8s_version, check binaries.kubeadm in values"
    exit 1
  fi

{{- if $envAll.Values.anchor.reconcile.os }}
  os_setup #!needs: os_setup
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

  # by default etcd is disabled - but if it was installed - turn this phase onn
  if [[ $(node_info_field "$node_info" etcd) == "enabled" ]]; then
    # do not skip etcd related phases
    [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
    # turn on etcd upgrade
    [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml" ] && sed "${SED_INPLACE[@]}" -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
  fi

  # we need to support cases when node wasn't even bootstrapped with bootstrap,
  # that's why we need to upload ClusterConfig and get claster-info
  if [ "${NODE_ROLE}" == "master" ] && [ -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]; then
    # kubeadm mutates the kubeconfig passed via --kubeconfig if it is a default one
    # (/etc/kubernetes/admin.conf). Operate on a throwaway copy of admin.conf so the
    # synced /etc/kubernetes/admin.conf on the host is not modified.
    tmp_dir="$(mktemp -d -p "${RECONCILE_DIR}")"
    cp "${ROOTFS}${KUBERNETES_DIR}/admin.conf" "${tmp_dir}/admin.conf"
    rc=0

    # kubeadm join and upgrade node take the ClusterConfiguration from the
    # kubeadm-config ConfigMap: kubeadm creates or updates it and kubelet-config.
    # It is needed only on controllers (kubeadm_action_required_rc works on controllers only)
    kubeadm_node_config > "${tmp_dir}/config.yaml"
    kubeadm init phase upload-config all --config "${tmp_dir}/config.yaml" --kubeconfig "${tmp_dir}/admin.conf" || rc=$?

    # cluster-info and the RBAC of the TLS bootstrap are created by kubeadm init
    # (bootstrap-token phase): missing on a cluster not created by it (taken over
    # from Airship) or removed
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

  # kubelet of another version than the cluster: the binary is upgraded
  [[ $(node_info_field "$node_info" kubelet_version) != $target_k8s_version ]] && kubelet_restart_required=true
{{- end }}

  # the anchor was restarted while the node was drained (e.g. the new kubelet
  # restarts containers): restart kubelet again, it uncordons the node
  [[ -n $(node_info_field "$node_info" kubelet_restarting) ]] && kubelet_restart_required=true

  kubeadm_action_required_rc "$node_info" && kubeadm_action_required=true
  if [[ $kubeadm_action_required == true ]]; then
    kubeadm_action "$node_info"
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
  touch "${RECONCILE_DIR}/done"

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
