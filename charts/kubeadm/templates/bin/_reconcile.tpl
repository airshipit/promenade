{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $sharedLibsContent :=  get $k8sConfDict "sharedLibsContent" -}}
#!/bin/bash
# Copyright 2025 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xeuo pipefail

# rootfs path (used to run mock tests. must be "" in real life)
ROOTFS="${ROOTFS:-}"
# files of the reconcile script only: script, service account, state, see
# ensure_fs (the files delivered by the chart are in /run/kubeadm)
RECONCILE_DIR={{ $envAll.Values.anchor.reconcile.host_dir | quote }}

kubectl() {
  command kubectl --kubeconfig "${RECONCILE_DIR}/kubeconfig" "$@"
}
# namespace of the anchor pod: its service account runs the kubelet restart job
NAMESPACE="$(cat "${RECONCILE_DIR}/sa/namespace")"

# config directories
KUBERNETES_DIR="/etc/kubernetes"

KUBERNETES_VERSION="$(sed -n 's/^ *kubernetesVersion: *\(.*\)/\1/p' /run/kubeadm/all/_kubeadm/ClusterConfiguration)"
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

{{/* adding shared bash functions */}}
{{ $sharedLibsContent }}
{{- if $envAll.Values.checks.reconcile }}
{{ get $k8sConfDict.sharedLibs "checks" }}
{{- end }}
# end of common functions

PATH="${BINARIES_DIR}:${PATH}"

cleanup_old_backups() {
  if [ -e "${ROOTFS}/etc/kubernetes/tmp/" ]; then
    for p in kubeadm-backup-etcd kubeadm-backup-manifests; do ls -d "${ROOTFS}/etc/kubernetes/tmp/$p-*" 2>/dev/null | sort | sed '$d' | xargs -r rm -rf || true; done
  fi
}

restart_kubelet() {
  local was_ready restarted heartbeat i
  was_ready=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  annotate_node "$KUBELET_RESTART_ANNOTATION" true
{{- if $envAll.Values.kubelet.drain }}
  kubectl drain "${NODE_NAME}" --pod-selector '!kubelet-restart' --ignore-daemonsets --delete-emptydir-data
{{- end }}

  # the clock of the node: the kubelet sets the heartbeat by it too
  restarted=$(date -u +%FT%TZ)
  # heredoc will take care of ${NODE_NAME} and etc
  job_name=$(kubectl create -n "${NAMESPACE}" -f - -o name <<EOF_DATA
{{ tuple $envAll "templates/bin/helpers/_kubelet_restart.yaml.tpl" $envAll | include "kubeadm.bundle.patched_template" }}
EOF_DATA
)

  kubectl wait -n "${NAMESPACE}" --for=condition=complete $job_name --timeout=600s

{{- if $envAll.Values.kubelet.drain }}
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
  if [[ $KUBELET_CURRENT_VERSION != $("${BINARIES_DIR}/kubelet" --version | awk '{print $2}') ]]; then
    echo "kubelet version mismatch"
    exit 1
  fi

  # the node is ready with its control plane down: a new kubelet version starts
  # the static pods again before the old ones free their ports, they are ready
  # after a back-off
  if [[ $NODE_ROLE == "master" ]]; then
    for i in $(seq 60); do
      kubectl wait -n kube-system --for=condition=ready pod -l tier=control-plane \
        --field-selector "spec.nodeName=${NODE_NAME}" --timeout=5s && return 0
      sleep 5
    done
    echo "the control plane of the node isn't ready after the restart"
    exit 1
  fi
}

# sets KUBEADM_ACTION_REQUIRED and KUBELET_RESTART_REQUIRED flags,
# returns 0 if any action is required
is_action_required() {
  local rc=1 # return code 1 means false

  if [[ $NODE_ROLE == "master" ]]; then
    current_cluster_config_sha256=$(kubeadm_config_sha256)
    if [[ -z $LAST_APPLIED_KUBEADM_CONFIG_SHA256 || $LAST_APPLIED_KUBEADM_CONFIG_SHA256 != $current_cluster_config_sha256 ]]; then
      KUBEADM_ACTION_REQUIRED=true
      rc=0
    fi
  fi

{{- if $envAll.Values.kubelet.restart  }}
  current_kubelet_config_sha256=$(kubelet_config_sha256)
  if [[ -z $LAST_APPLIED_KUBELET_CONFIG_SHA256 || $LAST_APPLIED_KUBELET_CONFIG_SHA256 != $current_kubelet_config_sha256 || $KUBELET_CURRENT_VERSION != $KUBERNETES_VERSION ]]; then
    KUBELET_RESTART_REQUIRED=true
    rc=0
  fi
{{- end }}

  return $rc
}

annotate_node() {
  kubectl annotate node --overwrite "$NODE_NAME" "$1=$2"
}

kubeadm() {
  if [[ "$1" == "version" ]]; then
    command "${BINARIES_DIR}/kubeadm" "$@"
  else
    command "${BINARIES_DIR}/kubeadm" --v=5 "$@"
  fi
}

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
    sync_kubelet_kubeconfig || true
    sync_kubeconfigs

    kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 300s
  fi
}

# kubelet must not be newer than the apiservers
wait_apiservers_upgraded() {
  local versions
  while true; do
    versions=$(kubectl get pods -n kube-system -l component=kube-apiserver \
      -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | sed 's/.*://' | sort -u)
    if [[ -z "$versions" || "$versions" == "$KUBERNETES_VERSION" ]]; then
      return 0
    fi
    echo "waiting for the apiservers to be upgraded to $KUBERNETES_VERSION: $versions"
    sleep 30
  done
}

{{- if $envAll.Values.deprecated.airship_migration.enabled }}

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

remove_if_exists() {
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
  remove_if_exists "${ROOTFS}{{ $file }}"
{{- end }}
  rm -f "${RECONCILE_DIR}/airship-migration"
}
{{- end }}

# the rebootstrap script runs on the node while its backups exist (the lock, see
# templates/bin/_rebootstrap.tpl): the node isn't touched until they are removed.
# The waiting file tells the rebootstrap script the pass doesn't go on
wait_rebootstrap() {
  while [ -e "${ROOTFS}"{{ $envAll.Values.bootstrap.rebootstrap_backup_dir | quote }} ]; do
    touch "${RECONCILE_DIR}/rebootstrap-wait"
    echo "rebootstrap: {{ $envAll.Values.bootstrap.rebootstrap_backup_dir }} exists, waiting for the end of the procedure (restore or backup-remove)"
    sleep 30
  done
  rm -f "${RECONCILE_DIR}/rebootstrap-wait"
}

wait_rebootstrap
sync_binaries kubeadm kubectl || true
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
guard_ca
{{- end }}

cleanup_old_backups

KUBEADM_ACTION_REQUIRED=false
KUBELET_RESTART_REQUIRED=false

CRI_RESTART_REQUIRED=false
{{- if $envAll.Values.cri.reconcile_install }}
sync_cri_install && CRI_RESTART_REQUIRED={{ $envAll.Values.cri.restart }}
{{- end }}
sync_cri && CRI_RESTART_REQUIRED={{ $envAll.Values.cri.restart }}
if [[ $CRI_RESTART_REQUIRED == true ]]; then
  restart_cri
fi
sync_kubeconfigs
sync_kubelet && KUBELET_RESTART_REQUIRED={{ $envAll.Values.kubelet.restart  }}
[[ $NODE_ROLE == "master" ]] || wait_apiservers_upgraded
sync_binary kubelet && KUBELET_RESTART_REQUIRED={{ $envAll.Values.kubelet.restart  }}

sync_certs
sync_kubeadm

# by default etcd is disabled - but if it was installed - turn this phase onn
if [[ $KUBERNETES_ETCD == "enabled" ]]; then
  # do not skip etcd related phases
  [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
  # turn on etcd upgrade
  [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml" ] && sed "${SED_INPLACE[@]}" -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
fi

# kubeadm config has to be up-to-date with what we have in values.
# It is needed only on controllers (is_action_required works on controllers only)
if [[ $NODE_ROLE == "master" && -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]]; then
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
if [ $NODE_ROLE == "master" ] && ! kubectl get cm -n kube-public cluster-info; then
  tmp_admin_conf="$(mktemp -p "${RECONCILE_DIR}" -t temp-kubeconfig.XXXXXX)"
  cp "${ROOTFS}/etc/kubernetes/admin.conf" "$tmp_admin_conf"
  rc=0
  kubeadm init phase bootstrap-token --kubeconfig "${tmp_admin_conf}" || rc=$?
  rm -f "$tmp_admin_conf"
  [ $rc -eq 0 ] || exit $rc
fi

{{- if $envAll.Values.deprecated.airship_migration.enabled }}

[[ $NODE_ROLE == "master" ]] && rename_cp_pods
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
  restart_kubelet
  LAST_APPLIED_KUBELET_CONFIG_SHA256="$(kubelet_config_sha256)"
  annotate_node "$KUBELET_ANNOTATION" "$LAST_APPLIED_KUBELET_CONFIG_SHA256"
fi
{{- if $envAll.Values.deprecated.airship_migration.enabled }}

airship_migration_cleanup
{{- end }}

{{- if $envAll.Values.checks.reconcile }}

# the anchor becomes ready only if the node checks pass
run_checks check_vip
{{- end }}

touch "${RECONCILE_DIR}/done"

# main loop
while true; do
  if [ -e "${RECONCILE_DIR}/stop" ] || is_action_required; then
    echo "Stopping"
    break
  fi
{{- if dig "reconcile" false ($envAll.Values.vip | default dict) }}
  # the node uses the haproxy VIP (configured by the bootstrap): follow the
  # control plane endpoints
  if [ -f "${ROOTFS}{{ $envAll.Values.haproxy.host_config_dir }}/haproxy.cfg" ]; then
    vip_anchor || true
  fi
{{- end }}
  sleep {{ $envAll.Values.anchor.reconcile.period }}
done
