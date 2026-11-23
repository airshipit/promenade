{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

# The functions of the reconcile script (templates/bin/_reconcile.sh.tpl): its
# reconcile function is in _.sh.tpl, it can be redefined in bundle.tpl. The
# environment of the anchor (ROOTFS, RECONCILE_DIR, NAMESPACE, KUBECONFIG, the
# kubeadm wrapper) is in the script.

#!define: KUBERNETES_DIR
# config directories
KUBERNETES_DIR="/etc/kubernetes"

#!define: KUBERNETES_VERSION
KUBERNETES_VERSION="$(sed -n 's/^ *kubernetesVersion: *\(.*\)/\1/p' /run/kubeadm/all/_kubeadm/ClusterConfiguration)"

#!define: NODE_STATE
CRI_SOCKET_ANNOTATION="kubeadm.alpha.kubernetes.io/cri-socket"
# set while the anchor keeps the node drained to restart kubelet
KUBELET_RESTART_ANNOTATION="kubelet-restart-in-progress"

# Node info
LAST_APPLIED_KUBEADM_CONFIG_SHA256=""
LAST_APPLIED_KUBELET_CONFIG_SHA256=""
CRI_SOCKET=""
KUBELET_CURRENT_VERSION=""
KUBERNETES_ETCD=""
KUBELET_RESTART_IN_PROGRESS=""

#!define: cleanup_old_backups
cleanup_old_backups() {
  if [ -e "${ROOTFS}/etc/kubernetes/tmp/" ]; then
    for p in kubeadm-backup-etcd kubeadm-backup-manifests; do ls -d "${ROOTFS}/etc/kubernetes/tmp/$p-*" 2>/dev/null | sort | sed '$d' | xargs -r rm -rf || true; done
  fi
}

#!define: kubelet_restart
#!needs: annotate_node, NODE_STATE
kubelet_restart() {
  local was_ready restarted heartbeat i
  was_ready=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  annotate_node "$KUBELET_RESTART_ANNOTATION" true
{{- if $envAll.Values.anchor.reconcile.kubelet_drain }}
  kubectl drain "${NODE_NAME}" --pod-selector '!kubelet-restart' --ignore-daemonsets --delete-emptydir-data
{{- end }}

  # the clock of the node: the kubelet sets the heartbeat by it too
  restarted=$(date -u +%FT%TZ)
  # heredoc will take care of ${NODE_NAME} and etc
  job_name=$(kubectl create -n "${NAMESPACE}" -f - -o name <<EOF_DATA
{{ tuple $envAll "templates/phases/modules/reconcile/_job-kubelet-restart.yaml" $envAll | include "kubeadm.bundle.patched_template" }}
EOF_DATA
)

  kubectl wait -n "${NAMESPACE}" --for=condition=complete $job_name --timeout=600s

{{- if $envAll.Values.anchor.reconcile.kubelet_drain }}
  kubectl uncordon "${NODE_NAME}"
{{- end }}
  kubectl annotate node "${NODE_NAME}" "${KUBELET_RESTART_ANNOTATION}-"

  # the new kubelet reports the status of the node once started (the heartbeat
  # of the conditions, the lease keeps the node alive in between)
  for i in $(seq 60); do
    heartbeat=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastHeartbeatTime}') || true
    [[ $heartbeat > $restarted ]] && break
    sleep 5
  done
  if [[ ! $heartbeat > $restarted ]]; then
    echo "kubelet didn't report the node after the restart"
    exit 1
  fi

  # a NotReady node (e.g. no CNI yet) doesn't become ready by the restart
  if [[ $was_ready == True ]]; then
    kubectl wait node --for=condition=ready "${NODE_NAME}" --timeout=60s
  fi

  KUBELET_CURRENT_VERSION=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
  if [[ $KUBELET_CURRENT_VERSION != $(kubelet --version | awk '{print $2}') ]]; then
    echo "kubelet version mismatch"
    exit 1
  fi

  # the node is ready with its control plane down: a new kubelet version starts
  # the static pods again before the old ones free their ports, they are ready
  # after a back-off
  if [ "${NODE_ROLE}" == "master" ]; then
    for i in $(seq 60); do
      kubectl wait -n kube-system --for=condition=ready pod -l tier=control-plane \
        --field-selector "spec.nodeName=${NODE_NAME}" --timeout=5s && return 0
      sleep 5
    done
    echo "the control plane of the node isn't ready after the restart"
    exit 1
  fi
}

#!define: is_action_required
#!needs: kubeadm_config_sha256, kubelet_config_sha256, KUBERNETES_VERSION, NODE_STATE
# sets KUBEADM_ACTION_REQUIRED and KUBELET_RESTART_REQUIRED flags,
# returns 0 if any action is required
is_action_required() {
  local rc=1 # return code 1 means false

  if [ "${NODE_ROLE}" == "master" ]; then
    current_cluster_config_sha256=$(kubeadm_config_sha256)
    if [[ -z $LAST_APPLIED_KUBEADM_CONFIG_SHA256 || $LAST_APPLIED_KUBEADM_CONFIG_SHA256 != $current_cluster_config_sha256 ]]; then
      KUBEADM_ACTION_REQUIRED=true
      rc=0
    fi
  fi

{{- if $envAll.Values.anchor.reconcile.kubelet_restart }}
  current_kubelet_config_sha256=$(kubelet_config_sha256)
  if [[ -z $LAST_APPLIED_KUBELET_CONFIG_SHA256 || $LAST_APPLIED_KUBELET_CONFIG_SHA256 != $current_kubelet_config_sha256 || $KUBELET_CURRENT_VERSION != $KUBERNETES_VERSION ]]; then
    KUBELET_RESTART_REQUIRED=true
    rc=0
  fi
{{- end }}

  return $rc
}

#!define: annotate_node
annotate_node() {
  kubectl annotate node --overwrite "$NODE_NAME" "$1=$2"
}

#!define: upload_kubeadm_config
#!needs: kubeadm_node_config, KUBERNETES_DIR
# kubeadm join and upgrade node take the ClusterConfiguration from the
# kubeadm-config ConfigMap:
# kubeadm creates or updates it and kubelet-config
upload_kubeadm_config() {
  local dir rc=0
  dir="$(mktemp -d -p "${RECONCILE_DIR}")"
  # kubeadm may rewrite the kubeconfig passed to it
  cp "${ROOTFS}${KUBERNETES_DIR}/admin.conf" "${dir}/admin.conf"
  kubeadm_node_config > "${dir}/config.yaml"
  kubeadm init phase upload-config all --config "${dir}/config.yaml" --kubeconfig "${dir}/admin.conf" || rc=$?
  rm -rf "${dir}"
  return $rc
}

#!define: rejoin_control_plane
#!needs: KUBERNETES_DIR, NODE_STATE
# the join configuration of the bootstrap script (the placeholder of the
# bootstrap token): the node bootstrapped by it joins again, e.g. its etcd
# member removed below. Its admin.conf instead of the token, without the
# phases of a new node (its certificates, kubeconfigs and kubelet are there).
# A failed join: as the join below
rejoin_control_plane() {
  local dir phase phases="" skip="preflight control-plane-prepare/download-certs control-plane-prepare/certs control-plane-prepare/kubeconfig kubelet-start control-plane-join wait-control-plane"
  if [ ! -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]; then
    echo "${KUBERNETES_DIR}/kubeadm/join_config.yaml needs the bootstrap token: the node has no admin.conf to join with"
    exit 1
  fi
  [[ $KUBERNETES_ETCD == "enabled" ]] || skip="${skip} check-etcd etcd-join"
  dir="$(mktemp -d -p "${RECONCILE_DIR}")"
  sed -e "s|^\( *kubeConfigPath:\).*|\1 ${KUBERNETES_DIR}/admin.conf|" -e '/^ *tlsBootstrapToken:/d' \
    "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml" > "${dir}/config.yaml"
  grep -q '^skipPhases:' "${dir}/config.yaml" || echo "skipPhases:" >> "${dir}/config.yaml"
  # the ones the configuration doesn't skip yet
  for phase in ${skip}; do
    grep -q "^ *- ${phase}\$" "${dir}/config.yaml" || phases="${phases} ${phase}"
  done
  awk -v phases="${phases}" '{ print } /^skipPhases:/ { n = split(phases, p, " "); for (i = 1; i <= n; i++) print "  - " p[i] }' \
    "${dir}/config.yaml" > "${dir}/rejoin.yaml"
  if ! kubeadm join --config "${dir}/rejoin.yaml"; then
    rm -rf "${dir}"
    if [[ $KUBERNETES_ETCD == "enabled" ]]; then
      echo "kubeadm join failed, performing reset to clean up local etcd member"
      kubeadm reset phase remove-etcd-member
      rm -f "${ROOTFS}${KUBERNETES_DIR}/manifests/etcd.yaml" || true
      sleep 30
    fi
    exit 1
  fi
  rm -rf "${dir}"
  # the join writes the manifests of the control plane again: the anchor is
  # ready once its pods are
  kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 300s
}

#!define: kubeadm_action
#!needs: annotate_node, rejoin_control_plane, kubelet_kubeconfig_sync_rc, kubeconfigs_sync, KUBERNETES_DIR, NODE_STATE
kubeadm_action() {
  if [ -z $CRI_SOCKET ]; then
    annotate_node "$CRI_SOCKET_ANNOTATION" "$(sed -n 's/^ *containerRuntimeEndpoint: *\(.*\)/\1/p' /run/kubeadm/all/_kubelet/kubelet_config.yaml)"
  fi

  # switching node to the controller
  if [[ ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" ||
       ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/kube-controller-manager.yaml" ||
       ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/kube-scheduler.yaml"  ]] ||
       [[ $KUBERNETES_ETCD == "enabled" && ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/etcd.yaml" ]]; then
    if grep -qF '${KUBEADM_TOKEN}' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml"; then
      # the node was bootstrapped by the chart in CA-only mode
      rejoin_control_plane
    elif ! kubeadm join --config "${KUBERNETES_DIR}/kubeadm/join_config.yaml"; then
      if [[ $KUBERNETES_ETCD == "enabled" ]]; then
        echo "kubeadm join failed, performing reset to clean up local etcd member"
        kubeadm reset phase remove-etcd-member
        rm -f "${ROOTFS}${KUBERNETES_DIR}/manifests/etcd.yaml" || true
        sleep 30
      fi
      exit 1
    fi
  else
    # the other masters may restart their control plane at the same time
    if ! kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 300s; then
      echo "control plane pods are not healthy, resetting the node"
      if [[ $KUBERNETES_ETCD == "enabled" ]]; then
        if ! kubectl wait --for=condition=ready pod -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l component=etcd --timeout 10s 2>/dev/null; then
          echo "performing reset to clean up local etcd member"
          kubeadm reset phase remove-etcd-member
          rm -f "${ROOTFS}${KUBERNETES_DIR}/manifests/etcd.yaml" || true
          sleep 30
        fi
      fi
      for component in kube-apiserver kube-controller-manager kube-scheduler; do
        # an API error isn't a reason to remove the manifest
        ready=$(kubectl get pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l component=$component -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}') || continue
        if [[ $ready != True ]]; then
          echo "Removing unhealthy static pod manifest for $component"
          rm -f "${ROOTFS}${KUBERNETES_DIR}/manifests/${component}.yaml"
          sleep 30
        fi
      done
      exit 1
    fi
    if [ $(kubectl get pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l tier=control-plane --no-headers | wc -l) -gt 0 ]; then
      kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l tier=control-plane --timeout 300s
    fi
    kubeadm upgrade node --config "${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"

    # kubeadm changes kubelet server address - enforcing it back
    kubelet_kubeconfig_sync_rc || true
    kubeconfigs_sync

    kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 300s
  fi
}

#!define: wait_apiservers_upgraded
#!needs: KUBERNETES_VERSION
# the version skew policy: kubelet must not be newer than any apiserver, by the
# minor version (the patch one of an image pinned by its digest and the build
# suffixes don't matter). Each is asked directly, through the VIP only one answers
wait_apiservers_upgraded() {
  local target endpoints endpoint versions
  target=$(echo "${KUBERNETES_VERSION#v}" | cut -d . -f 1-2)
  while true; do
    endpoints=$(kubectl get pods -n kube-system -l component=kube-apiserver \
      -o jsonpath='{range .items[*]}{.metadata.annotations.kubeadm\.kubernetes\.io/kube-apiserver\.advertise-address\.endpoint}{"\n"}{end}')
    # major.minor of each (the minor may be "37+"), 0 for the one that doesn't answer
    # (being restarted). Its certificate may lack the IP of the node, the name of
    # the service is in every one
    versions=$(for endpoint in $endpoints; do
      kubectl get --raw /version --server "https://${endpoint}" --tls-server-name kubernetes \
        | awk -F '"' '/"major"/ { major = $4 } /"minor"/ { print major "." ($4 + 0) }' || echo 0
    done | sort -u)
    # none is older than the target: the oldest of them and the target is the target
    [[ -z "$versions" || "$(printf '%s\n' "$versions" "$target" | sort -V | head -n 1)" == "$target" ]] && return 0
    echo "waiting for the apiservers to be upgraded to $target: $versions"
    sleep 30
  done
}

#!define: apiserver_files_sha256
# the checksums of the files of the command line of the apiserver of the node
# (certificates, keys, configurations), nothing if the node doesn't run it
apiserver_files_sha256() {
  local manifest="${ROOTFS}${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" file
  [ -f "${manifest}" ] || return 0
  for file in $(sed -n 's/^ *- --[^=]*=\(\/[^,]*\)$/\1/p' "${manifest}"); do
    [ -f "${ROOTFS}${file}" ] && sha256sum "${ROOTFS}${file}"
  done
  return 0
}

#!define: apiserver_restart
#!needs: certs_manifest_flag, KUBERNETES_DIR
# the apiserver of the node starts again with all the files of its command
# line: it reloads some of them only (not its client certificates). kubelet
# starts the stopped static pod again
apiserver_restart() {
  local pods pod port i
  port=$(certs_manifest_flag "${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" secure-port)
  # not in the for list: errexit doesn't see a failure there
  pods=$(crictl pods -q --namespace kube-system --label component=kube-apiserver)
  for pod in ${pods}; do
    # the default RPC timeout of crictl is 2s: stopping a sandbox takes longer
    crictl --timeout 60s stopp "${pod}"
  done
  for i in $(seq 150); do
    curl -ksf --max-time 5 "https://127.0.0.1:${port}/readyz" > /dev/null && return 0
    sleep 2
  done
  echo "the apiserver isn't ready after the restart"
  exit 1
}

{{- if $envAll.Values.deprecated.airship_migration.enabled }}

#!define: rename_cp_pods
#!needs: KUBERNETES_DIR
# MIGRATION from Airship (remove together with the cleanup below): the static
# pods of Airship renamed to the kubeadm ones, a marker for the cleanup
rename_cp_pods() {
  cp_pods="etcd apiserver controller-manager scheduler"
  for cp_pod in $cp_pods; do
    src_path="${ROOTFS}${KUBERNETES_DIR}/manifests/kubernetes-${cp_pod}.yaml"
    dst_path="${ROOTFS}${KUBERNETES_DIR}/manifests/kube-${cp_pod}.yaml"
    component="kube-${cp_pod}"
    if [[ $cp_pod == "etcd" ]]; then
      dst_path="${ROOTFS}${KUBERNETES_DIR}/manifests/${cp_pod}.yaml"
      component="${cp_pod}"
    fi
    if [ -e "$src_path" ]; then
      touch "${RECONCILE_DIR}/airship-migration"
      if [ -e "$dst_path" ]; then
        echo "INFO: ${dst_path} already exists; removing stale ${src_path} without overwriting"
        rm -f "$src_path"
        continue
      fi
      if [[ ! -s "$src_path" ]]; then
        echo "WARNING: ${src_path} is empty (previously truncated); removing stale file, skipping rename"
        rm -f "$src_path"
        continue
      fi

      if [ $(kubectl get pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l component=$component --no-headers | wc -l) -gt 0 ]; then
        kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l component=$component --timeout=180s
      fi
      cp "$src_path" "$dst_path"
      rm "$src_path"
      sed -i -e "s/name: kubernetes-$cp_pod/name: $component/g" "$dst_path"
      sleep 30
      attempts=0
      max_attempts=3
      until kubectl wait --for=condition=ready pod -n kube-system --field-selector spec.nodeName=$NODE_NAME -l component=$component --timeout=180s; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$max_attempts" ]; then
          echo "ERROR: $component pod not ready after ${max_attempts} attempts (180s each) following rename; aborting"
          exit 1
        fi
        echo "WARNING: $component pod not ready within 180s after rename (attempt ${attempts}/${max_attempts}); retrying"
      done
    fi
  done
}

#!define: remove_if_exists
remove_if_exists() {
  local path="$1"
  if [ -e "$path" ]; then
    if [ -d "$path" ]; then rm -rf "$path"; else rm -f "$path"; fi
  fi
}

#!define: airship_migration_cleanup
#!needs: remove_if_exists
# MIGRATION from Airship: its files (deprecated.airship_migration),
# once kubeadm has written the static pods again (the end of the pass). Only
# on a node marked as one of Airship (renamed static pods, no annotations of
# the chart): the chart writes to /etc/kubernetes/apiserver too
airship_migration_cleanup() {
  [ -e "${RECONCILE_DIR}/airship-migration" ] || return 0
{{- range $file := $envAll.Values.deprecated.airship_migration.files_to_delete }}
  remove_if_exists "${ROOTFS}{{ $file }}"
{{- end }}
  rm -f "${RECONCILE_DIR}/airship-migration"
}
{{- end }}

#!define: wait_rebootstrap
#!needs: backup_exists_rc
# the rebootstrap script runs on the node while its backups exist (the lock, see
# bootstrap.profiles.rebootstrap): the node isn't touched until they are removed.
# The waiting file tells the rebootstrap script the pass doesn't go on
wait_rebootstrap() {
  while backup_exists_rc; do
    touch "${RECONCILE_DIR}/rebootstrap-wait"
    echo "rebootstrap: {{ $envAll.Values.backup.dir }} exists, waiting for the end of the procedure (backup restore or backup remove)"
    sleep 30
  done
  rm -f "${RECONCILE_DIR}/rebootstrap-wait"
}
