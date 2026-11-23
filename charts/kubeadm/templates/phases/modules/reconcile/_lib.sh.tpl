{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

# The functions of the reconcile script (templates/bin/_reconcile.sh.tpl): its
# reconcile function is in _.sh.tpl, it can be redefined in bundle.tpl. The
# environment of the anchor (ROOTFS, RECONCILE_DIR, NAMESPACE, KUBECONFIG, the
# kubeadm wrapper) is in the script.
# reconcile_guard is the other side of wait_rebootstrap: the rebootstrap phase
# locking the reconcile.

#!define: KUBERNETES_DIR
# config directories
KUBERNETES_DIR="/etc/kubernetes"

#!define: RECONCILE_DIR
# the reconcile script has it in its environment, the bootstrap one needs it
# for reconcile_guard
RECONCILE_DIR={{ $envAll.Values.anchor.reconcile.host_dir | quote }}

#!define: NODE_INFO_ANNOTATIONS
# the annotations of the state of the node (node_info_*)
# the configurations the node runs with: the reconcile applies the kubeadm
# (control plane nodes) and the kubelet configuration only if the node runs
# with another one (the bootstrap writes them too: kubelet_mark_applied,
# kubeadm_mark_applied)
KUBEADM_CFG_ANNOTATION="last-applied-kubeadm-cfg-sha256"
KUBELET_CFG_ANNOTATION="last-applied-kubelet-cfg-sha256"
# set while the anchor keeps the node drained to restart kubelet
KUBELET_RESTART_ANNOTATION="kubelet-restarting"
# annotation which is used by kubeadm binary
CRI_SOCKET_ANNOTATION="kubeadm.alpha.kubernetes.io/cri-socket"

#!define: node_info_load
#!needs: NODE_INFO_ANNOTATIONS
# the state of the node from the API, node_info_field reads its fields
node_info_load() {
  kubectl get node "$NODE_NAME" -o jsonpath="{.metadata.annotations.$KUBEADM_CFG_ANNOTATION}|{.metadata.annotations.$KUBELET_CFG_ANNOTATION}|{.metadata.annotations.$CRI_SOCKET_ANNOTATION}|{.status.nodeInfo.kubeletVersion}|{.metadata.labels.kubernetes-etcd}|{.metadata.annotations.$KUBELET_RESTART_ANNOTATION}"
}

#!define: node_info_field
# the field $2 of the state of the node $1 (node_info_load)
node_info_field() {
  local kubeadm_applied kubelet_applied cri_socket kubelet_version etcd kubelet_restarting
  IFS='|' read -r kubeadm_applied kubelet_applied cri_socket kubelet_version etcd kubelet_restarting <<< "$1"
  case "$2" in
    kubeadm_applied) echo "${kubeadm_applied}" ;;
    kubelet_applied) echo "${kubelet_applied}" ;;
    cri_socket) echo "${cri_socket}" ;;
    kubelet_version) echo "${kubelet_version}" ;;
    etcd) echo "${etcd}" ;;
    kubelet_restarting) echo "${kubelet_restarting}" ;;
    *) echo "node_info_field: unknown field $2" >&2; exit 1 ;;
  esac
}

#!define: node_info_update
#!needs: NODE_INFO_ANNOTATIONS
# writes the field $1 of the state of the node (node_info_field) with the value
# $2, an empty one removes it. A function writing it, also through the
# functions it calls, has node_info_update in its needs: after its call
# node_info is loaded again before it is read
node_info_update() {
  local annotation
  case "$1" in
    kubeadm_applied) annotation="$KUBEADM_CFG_ANNOTATION" ;;
    kubelet_applied) annotation="$KUBELET_CFG_ANNOTATION" ;;
    cri_socket) annotation="$CRI_SOCKET_ANNOTATION" ;;
    kubelet_restarting) annotation="$KUBELET_RESTART_ANNOTATION" ;;
    *) echo "node_info_update: the field $1 isn't written by the reconcile" >&2; exit 1 ;;
  esac
  if [ -n "$2" ]; then
    kubectl annotate node --overwrite "$NODE_NAME" "${annotation}=$2"
  else
    kubectl annotate node "$NODE_NAME" "${annotation}-"
  fi
}

#!define: node_info_update_wait
#!needs: node_info_update
# node_info_update until it works, 5 minutes at most: right after the join the
# node isn't registered yet (kubelet goes through the VIP, it starts the
# haproxy static pod first, as the kubeadm timeouts). Then only a warning: the
# reconcile applies the configurations again, it writes the field later
node_info_update_wait() {
  local n=1
  until node_info_update "$@"; do
    if [ "$n" -ge 150 ]; then
      echo "WARNING: $1 of the node isn't written, the reconcile applies the configurations again" >&2
      return 0
    fi
    n=$((n + 1))
    sleep 2
  done
}

#!define: kubelet_restart_by_job
#!needs: node_info_update
kubelet_restart_by_job() {
  local was_ready restarted heartbeat i version job_name
  was_ready=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  node_info_update kubelet_restarting true
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
  node_info_update kubelet_restarting ""

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

  version=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
  if [[ $version != $(kubelet --version | awk '{print $2}') ]]; then
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

#!define: kubeadm_action
#!needs: node_info_update, node_info_load, kubelet_kubeconfig_sync_rc, kubeconfig_sync, KUBERNETES_DIR, node_info_field

# kubeadm_action's helper:
# the join configuration of the bootstrap script (the placeholder of the
# bootstrap token): the node bootstrapped by it joins again, e.g. its etcd
# member removed below. Its admin.conf instead of the token, without the
# phases of a new node (its certificates, kubeconfigs and kubelet are there).
# A failed join: as the join below
_rejoin_control_plane() {
  local dir phase phases="" skip="preflight control-plane-prepare/download-certs control-plane-prepare/certs control-plane-prepare/kubeconfig kubelet-start control-plane-join wait-control-plane"
  if [ ! -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]; then
    echo "${KUBERNETES_DIR}/kubeadm/join_config.yaml needs the bootstrap token: the node has no admin.conf to join with"
    exit 1
  fi
  [[ $(node_info_field "$1" etcd) == "enabled" ]] || skip="${skip} check-etcd etcd-join"
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
    if [[ $(node_info_field "$1" etcd) == "enabled" ]]; then
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

# kubeadm with the state of the node $1 (node_info_load)
kubeadm_action() {
  local node_info="$1"
  local component ready
  if [ -z "$(node_info_field "$node_info" cri_socket)" ]; then
    node_info_update cri_socket "$(sed -n 's/^ *containerRuntimeEndpoint: *\(.*\)/\1/p' /run/kubeadm/all/_kubelet/kubelet_config.yaml)"
    node_info=$(node_info_load)
  fi

  # switching node to the controller
  if [[ ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" ||
       ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/kube-controller-manager.yaml" ||
       ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/kube-scheduler.yaml"  ]] ||
       [[ $(node_info_field "$node_info" etcd) == "enabled" && ! -f "${ROOTFS}${KUBERNETES_DIR}/manifests/etcd.yaml" ]]; then
    if grep -qF '${KUBEADM_TOKEN}' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml"; then
      # the node was bootstrapped by the chart in CA-only mode
      _rejoin_control_plane "$node_info"
    elif ! kubeadm join --config "${KUBERNETES_DIR}/kubeadm/join_config.yaml"; then
      if [[ $(node_info_field "$node_info" etcd) == "enabled" ]]; then
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
      if [[ $(node_info_field "$node_info" etcd) == "enabled" ]]; then
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
    kubeconfig_sync

    kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 300s
  fi
}

#!define: wait_apiservers_upgraded
# the version skew policy: kubelet $1 must not be newer than any apiserver, by
# the minor version (the patch one of an image pinned by its digest and the
# build suffixes don't matter). Each is asked directly, through the VIP only one
# answers
wait_apiservers_upgraded() {
  local target endpoints endpoint versions
  target=$(echo "${1#v}" | cut -d . -f 1-2)
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

#!define: static_pod_flag
# the value of the flag --$2 of the static pod manifest $1: the command line the
# component runs with (kubeadm wrote it, the patches may have changed it)
static_pod_flag() {
  [ -f "${ROOTFS}$1" ] || return 0
  sed -n "s/^ *- --$2=//p" "${ROOTFS}$1" | head -n 1
}

#!define: static_pods_stop
# the static pods of the control plane, the given components (all of them
# without arguments): kubelet starts them again, e.g. with the new
# certificates. The rebootstrap stops etcd of all the control plane nodes at
# once
static_pods_stop() {
  local component pods pod
  if [ "${NODE_ROLE}" != "master" ]; then
    echo "not a control plane node"
    return 0
  fi
  [ $# -gt 0 ] || set -- kube-apiserver kube-controller-manager kube-scheduler etcd
  for component in "$@"; do
    # not in the for list: errexit doesn't see a failure there
    pods=$(crictl pods -q --namespace kube-system --label "component=${component}")
    for pod in ${pods}; do
      # the default RPC timeout of crictl is 2s: stopping a sandbox takes longer
      crictl --timeout 60s stopp "${pod}"
    done
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
#!needs: static_pod_flag, static_pods_stop, KUBERNETES_DIR
# the apiserver of the node starts again with all the files of its command
# line: it reloads some of them only (not its client certificates). kubelet
# starts the stopped static pod again
apiserver_restart() {
  local port i
  port=$(static_pod_flag "${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" secure-port)
  static_pods_stop kube-apiserver
  for i in $(seq 150); do
    curl -ksf --max-time 5 "https://127.0.0.1:${port}/readyz" > /dev/null && return 0
    sleep 2
  done
  echo "the apiserver isn't ready after the restart"
  exit 1
}

#!define: wait_rebootstrap
#!needs: backup_exists_rc
# the rebootstrap script runs on the node while its backups exist (the lock, see
# phase_runner.profiles.rebootstrap): the node isn't touched until they are removed.
# The waiting file tells the rebootstrap script the pass doesn't go on
wait_rebootstrap() {
  while backup_exists_rc; do
    touch "${RECONCILE_DIR}/rebootstrap-wait"
    echo "rebootstrap: {{ $envAll.Values.backup.dir }} exists, waiting for the end of the procedure (backup restore or backup remove)"
    sleep 30
  done
  rm -f "${RECONCILE_DIR}/rebootstrap-wait"
}

#!define: reconcile_guard
#!needs: RECONCILE_DIR

# reconcile_guard's helper: the reconcile passes going on on the node: the
# reconcile processes neither done nor waiting for the rebootstrap (the files of
# the anchor are in the mount namespace of its pod)
_reconcile_in_flight() {
  local pid
  for pid in $(pgrep -f "^/bin/bash ${RECONCILE_DIR}/reconcile" || true); do
    [ -e "/proc/${pid}/root${RECONCILE_DIR}/done" ] ||
      [ -e "/proc/${pid}/root${RECONCILE_DIR}/rebootstrap-wait" ] ||
      echo "${pid}"
  done
}

# the anchors of the node mustn't put the certificates of the values in the
# cluster back: they wait while the backups exist (the lock). The passes going
# on finish first
reconcile_guard() {
  local script pids deadline
  # kubelet keeps the ConfigMap volumes up to date: the script a restarted
  # anchor runs
  for script in "${ROOTFS}"/var/lib/kubelet/pods/*/volumes/kubernetes.io~configmap/bin/reconcile; do
    [ -f "${script}" ] || continue
    if ! grep -q wait_rebootstrap "${script}"; then
      echo "the anchor of ${script} doesn't wait for the rebootstrap: deploy the chart with it first" >&2
      return 1
    fi
  done
  mkdir -p -m 0700 "${ROOTFS}{{ $envAll.Values.backup.dir }}"
  deadline=$((SECONDS + {{ $envAll.Values.phase_runner.rebootstrap_reconcile_timeout | int }}))
  while pids=$(_reconcile_in_flight) && [ -n "${pids}" ]; do
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      echo "the reconcile passes $(echo ${pids}) didn't finish in {{ $envAll.Values.phase_runner.rebootstrap_reconcile_timeout | int }}s, the lock {{ $envAll.Values.backup.dir }} is kept" >&2
      return 1
    fi
    echo "waiting for the reconcile passes $(echo ${pids})"
    sleep 10
  done
  echo "the reconcile is locked: {{ $envAll.Values.backup.dir }}"
}

{{- if $envAll.Values.deprecated.airship_migration.enabled }}

#!define: rename_cp_pods
#!needs: KUBERNETES_DIR
# MIGRATION from Airship (remove together with the cleanup below): the static
# pods of Airship renamed to the kubeadm ones, a marker for the cleanup
rename_cp_pods() {
  local cp_pods cp_pod src_path dst_path component attempts max_attempts
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

#!define: airship_migration_cleanup

# airship_migration_cleanup's helper
_remove_if_exists() {
  local path="$1"
  if [ -e "$path" ]; then
    if [ -d "$path" ]; then rm -rf "$path"; else rm -f "$path"; fi
  fi
}

# MIGRATION from Airship: its files (deprecated.airship_migration),
# once kubeadm has written the static pods again (the end of the pass). Only
# on a node marked as one of Airship (renamed static pods, no annotations of
# the chart): the chart writes to /etc/kubernetes/apiserver too
airship_migration_cleanup() {
  [ -e "${RECONCILE_DIR}/airship-migration" ] || return 0
{{- range $file := $envAll.Values.deprecated.airship_migration.files_to_delete }}
  _remove_if_exists "${ROOTFS}{{ $file }}"
{{- end }}
  rm -f "${RECONCILE_DIR}/airship-migration"
}
{{- end }}

