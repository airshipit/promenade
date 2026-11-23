{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

#!define: reconcile
#!needs: KUBERNETES_DIR
#!needs: KUBERNETES_VERSION
#!needs: NODE_STATE
#!needs: annotate_node
#!needs: annotations
#!needs: apiserver_files_sha256
#!needs: apiserver_restart
#!needs: binaries_sync
#!needs: binary_kubernetes_sync_rc
#!needs: certs_sync
#!needs: cleanup_old_backups
#!needs: cri_restart
#!needs: cri_sync_rc
#!needs: is_action_required
#!needs: kubeadm_action
#!needs: kubeadm_config_sha256
#!needs: kubeadm_sync
#!needs: kubeconfigs_sync
#!needs: kubelet_config_sha256
#!needs: kubelet_restart
#!needs: kubelet_sync_rc
#!needs: upload_kubeadm_config
#!needs: wait_apiservers_upgraded
#!needs: wait_rebootstrap
# one pass (the state of the node, the files of the chart synced, the changes
# applied: kubeadm, the restart of kubelet, the node checks), the anchor is
# ready, then the main loop: a change needing a new pass ends it (the anchor
# restarts), the VIP the node was bootstrapped with follows the control plane
# endpoints meanwhile
reconcile() {
  wait_rebootstrap
  binaries_sync kubeadm kubectl
  # kubectl may be installed just above
  NODE_INFO=$(kubectl get node $NODE_NAME -o jsonpath="{.metadata.annotations.$KUBEADM_ANNOTATION}|{.metadata.annotations.$KUBELET_ANNOTATION}|{.metadata.annotations.$CRI_SOCKET_ANNOTATION}|{.status.nodeInfo.kubeletVersion}|{.metadata.labels.kubernetes-etcd}|{.metadata.annotations.$KUBELET_RESTART_ANNOTATION}")
  IFS='|' read -r LAST_APPLIED_KUBEADM_CONFIG_SHA256 LAST_APPLIED_KUBELET_CONFIG_SHA256 CRI_SOCKET KUBELET_CURRENT_VERSION KUBERNETES_ETCD KUBELET_RESTART_IN_PROGRESS <<<$NODE_INFO

  # no trace of the bootstrap or of a reconcile (e.g. a cluster taken over from
  # Airship): the anchors of all the nodes may start together, sleep randomly up
  # to 30 seconds
  if [[ -z $LAST_APPLIED_KUBEADM_CONFIG_SHA256 && -z $LAST_APPLIED_KUBELET_CONFIG_SHA256 ]]; then
    sleep $(shuf -i 1-30 -n 1)
  fi
  {{- if $envAll.Values.deprecated.airship_migration.enabled }}

  # MIGRATION from Airship: a node without the annotations of the chart (any
  # role), its files are removed at the end of the pass
  if [[ -z $LAST_APPLIED_KUBEADM_CONFIG_SHA256 && -z $LAST_APPLIED_KUBELET_CONFIG_SHA256 ]]; then
    touch "${RECONCILE_DIR}/airship-migration"
  fi
  {{- end }}
  # if isn't specified - kubeadm uses the version which corresponds to the binary
  [ -z "$KUBERNETES_VERSION" ] && KUBERNETES_VERSION=$(kubeadm version -o short)

  if [[ $(kubeadm version -o short) != "$KUBERNETES_VERSION" ]]; then
    echo "kubeadm $(kubeadm version -o short) on the node doesn't match kubernetesVersion $KUBERNETES_VERSION, check binaries.kubeadm in values"
    exit 1
  fi

  {{- if $envAll.Values.anchor.reconcile.ca_guard }}
  # before any sync: the files of the node are left as they are
  certs_guard_ca #!needs: certs_guard_ca
  {{- end }}

  cleanup_old_backups

  KUBEADM_ACTION_REQUIRED=false
  KUBELET_RESTART_REQUIRED=false

  CRI_RESTART_REQUIRED=false
  {{- if $envAll.Values.anchor.reconcile.cri_install }}
  binary_cri_sync_rc && CRI_RESTART_REQUIRED={{ $envAll.Values.anchor.reconcile.cri_restart }} #!needs: binary_cri_sync_rc
  {{- end }}
  cri_sync_rc && CRI_RESTART_REQUIRED={{ $envAll.Values.anchor.reconcile.cri_restart }}
  if [[ $CRI_RESTART_REQUIRED == true ]]; then
    cri_restart
  fi
  kubeconfigs_sync
  kubelet_sync_rc && KUBELET_RESTART_REQUIRED={{ $envAll.Values.anchor.reconcile.kubelet_restart }}
  [ "${NODE_ROLE}" == "master" ] || wait_apiservers_upgraded
  binary_kubernetes_sync_rc kubelet && KUBELET_RESTART_REQUIRED={{ $envAll.Values.anchor.reconcile.kubelet_restart }}

  # the apiserver restarts if the sync changed its files
  APISERVER_FILES_SHA256="$(apiserver_files_sha256)"
  certs_sync
  kubeadm_sync
  [ "$(apiserver_files_sha256)" == "${APISERVER_FILES_SHA256}" ] || apiserver_restart

  # by default etcd is disabled - but if it was installed - turn this phase onn
  if [[ $KUBERNETES_ETCD == "enabled" ]]; then
    # do not skip etcd related phases
    [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
    # turn on etcd upgrade
    [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml" ] && sed "${SED_INPLACE[@]}" -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
  fi

  # kubeadm config has to be up-to-date with what we have in values.
  # It is needed only on controllers (is_action_required works on controllers only)
  if [ "${NODE_ROLE}" == "master" ] && [ -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]; then
    upload_kubeadm_config
  fi

  # cluster-info and the RBAC of the TLS bootstrap are created by kubeadm init
  # (bootstrap-token phase): missing on a cluster not created by it (taken over
  # from Airship) or removed
  # kubeadm mutates the kubeconfig passed via --kubeconfig if it is a default one
  # (/etc/kubernetes/admin.conf). Operate on a throwaway copy of admin.conf so the
  # synced /etc/kubernetes/admin.conf on the host is not modified.
  # (TODO) move this check prior to kubeadm join command, as well add a check if kubeconfig
  # has been modified due to cert rotation
  if [ "${NODE_ROLE}" == "master" ] && ! kubectl get cm -n kube-public cluster-info; then
    tmp_admin_conf="$(mktemp -p "${RECONCILE_DIR}" -t temp-kubeconfig.XXXXXX)"
    cp "${ROOTFS}/etc/kubernetes/admin.conf" "$tmp_admin_conf"
    rc=0
    kubeadm init phase bootstrap-token --kubeconfig "${tmp_admin_conf}" || rc=$?
    rm -f "$tmp_admin_conf"
    [ $rc -eq 0 ] || exit $rc
  fi

  {{- if $envAll.Values.deprecated.airship_migration.enabled }}

  [ "${NODE_ROLE}" == "master" ] && rename_cp_pods #!needs: rename_cp_pods
  {{- end }}


  is_action_required || true
  # the anchor was restarted while the node was drained (e.g. the new kubelet
  # restarts containers): restart kubelet again, it uncordons the node
  [[ -n $KUBELET_RESTART_IN_PROGRESS ]] && KUBELET_RESTART_REQUIRED=true

  if [[ $KUBEADM_ACTION_REQUIRED == true ]]; then
    kubeadm_action
    LAST_APPLIED_KUBEADM_CONFIG_SHA256="$(kubeadm_config_sha256)"
    annotate_node "$KUBEADM_ANNOTATION" "$LAST_APPLIED_KUBEADM_CONFIG_SHA256"
  fi

  if [[ $KUBELET_RESTART_REQUIRED == true ]]; then
    kubelet_restart
    LAST_APPLIED_KUBELET_CONFIG_SHA256="$(kubelet_config_sha256)"
    annotate_node "$KUBELET_ANNOTATION" "$LAST_APPLIED_KUBELET_CONFIG_SHA256"
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
    if [ -e "${RECONCILE_DIR}/stop" ] || is_action_required; then
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
