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
KUBEADM_ANNOTATION="last-applied-kubeadm-cfg-sha256"
KUBELET_ANNOTATION="last-applied-kubelet-cfg-sha256"
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

# sleep randomly up to 30 seconds
sleep $(shuf -i 1-30 -n 1)

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

#remove_if_exists() {
#  path="$1"
#  if [ -e "$path" ]; then
#    if [ -d "$path" ]; then rm -rf $path; else rm -f "$path"; fi
#  fi
#}

#cleanup_old_configs() {
#
{{/*
#{{- range $file := .Values.const.files_to_delete }}
#  remove_if_exists "${ROOTFS}{{ $file }}"
#{{- end }}
*/}}
#  echo "cleanup_old_configs is done"
#}

restart_kubelet() {
  annotate_node "$KUBELET_RESTART_ANNOTATION" true
{{- if $envAll.Values.kubelet.drain }}
  kubectl drain "${NODE_NAME}" --pod-selector '!kubelet-restart' --ignore-daemonsets --delete-emptydir-data
{{- end }}

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
  kubectl wait node --for=condition=ready "${NODE_NAME}" --timeout=60s

  sleep 60

  KUBELET_CURRENT_VERSION=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
  if [[ $KUBELET_CURRENT_VERSION != $("${BINARIES_DIR}/kubelet" --version | awk '{print $2}') ]]; then
    echo "kubelet version mismatch"
    exit 1
  fi

  sleep 60
}

# sets KUBEADM_ACTION_REQUIRED and KUBELET_RESTART_REQUIRED flags,
# returns 0 if any action is required
is_action_required() {
  local rc=1 # return code 1 means false

  if [[ $NODE_ROLE == "master" ]]; then
    current_cluster_config_sha256=$(sha256sum < /run/kubeadm/all/_kubeadm/ClusterConfiguration | cut -d ' ' -f 1)
    if [[ -z $LAST_APPLIED_KUBEADM_CONFIG_SHA256 || $LAST_APPLIED_KUBEADM_CONFIG_SHA256 != $current_cluster_config_sha256 ]]; then
      KUBEADM_ACTION_REQUIRED=true
      rc=0
    fi
  fi

{{- if $envAll.Values.kubelet.restart  }}
  current_kubelet_config_sha256=$(sha256sum < /run/kubeadm/all/_kubelet/kubelet_config.yaml | cut -d ' ' -f 1)
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
  # the node name isn't always the hostname kubeadm defaults to
  cat > "${dir}/config.yaml" << EOF_CONFIG
apiVersion: $(sed -n 's/^apiVersion: *//p' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/ClusterConfiguration" | head -n 1)
kind: InitConfiguration
nodeRegistration:
  name: ${NODE_NAME}
  criSocket: $(sed -n 's/^ *containerRuntimeEndpoint: *\(.*\)/\1/p' "${ROOTFS}/var/lib/kubelet/config.yaml")
---
$(cat "${ROOTFS}${KUBERNETES_DIR}/kubeadm/ClusterConfiguration")
---
$(cat "${ROOTFS}/var/lib/kubelet/config.yaml")
EOF_CONFIG
  kubeadm init phase upload-config all --config "${dir}/config.yaml" --kubeconfig "${dir}/admin.conf" || rc=$?
  rm -rf "${dir}"
  return $rc
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
    if ! kubeadm join --config "${KUBERNETES_DIR}/kubeadm/join_config.yaml"; then
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

# migrate from airship names
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

sync_binaries kubeadm kubectl || true
# kubectl may be installed just above
NODE_INFO=$(kubectl get node $NODE_NAME -o jsonpath="{.metadata.annotations.$KUBEADM_ANNOTATION}|{.metadata.annotations.$KUBELET_ANNOTATION}|{.metadata.annotations.$CRI_SOCKET_ANNOTATION}|{.status.nodeInfo.kubeletVersion}|{.metadata.labels.kubernetes-etcd}|{.metadata.annotations.$KUBELET_RESTART_ANNOTATION}")
IFS='|' read -r LAST_APPLIED_KUBEADM_CONFIG_SHA256 LAST_APPLIED_KUBELET_CONFIG_SHA256 CRI_SOCKET KUBELET_CURRENT_VERSION KUBERNETES_ETCD KUBELET_RESTART_IN_PROGRESS <<<$NODE_INFO
# if isn't specified - kubeadm uses the version which corresponds to the binary
[ -z "$KUBERNETES_VERSION" ] && KUBERNETES_VERSION=$(kubeadm version -o short)

if [[ $(kubeadm version -o short) != "$KUBERNETES_VERSION" ]]; then
  echo "kubeadm $(kubeadm version -o short) on the node doesn't match kubernetesVersion $KUBERNETES_VERSION, check binaries.kubeadm in values"
  exit 1
fi

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
  [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/init_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/init_config.yaml" #TODO: to verify
  # turn on etcd upgrade
  [ -f "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml" ] && sed "${SED_INPLACE[@]}" -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${ROOTFS}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
fi

# kubeadm config has to be up-to-date with what we have in values.
# It is needed only on controllers (is_action_required works on controllers only)
if [[ $NODE_ROLE == "master" && -f "${ROOTFS}${KUBERNETES_DIR}/admin.conf" ]]; then
  upload_kubeadm_config
fi

# migration from Airship to kubeadm
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

# migration from Airship to kubeadm
[[ $NODE_ROLE == "master" ]] && rename_cp_pods


is_action_required || true
# the anchor was restarted while the node was drained (e.g. the new kubelet
# restarts containers): restart kubelet again, it uncordons the node
[[ -n $KUBELET_RESTART_IN_PROGRESS ]] && KUBELET_RESTART_REQUIRED=true

if [[ $KUBEADM_ACTION_REQUIRED == true ]]; then
  kubeadm_action
  LAST_APPLIED_KUBEADM_CONFIG_SHA256="$(sha256sum < /run/kubeadm/all/_kubeadm/ClusterConfiguration | cut -d ' ' -f 1)"
  annotate_node "$KUBEADM_ANNOTATION" "$LAST_APPLIED_KUBEADM_CONFIG_SHA256"
fi

if [[ $KUBELET_RESTART_REQUIRED == true ]]; then
  restart_kubelet
  LAST_APPLIED_KUBELET_CONFIG_SHA256="$(sha256sum < /run/kubeadm/all/_kubelet/kubelet_config.yaml | cut -d ' ' -f 1)"
  annotate_node "$KUBELET_ANNOTATION" "$LAST_APPLIED_KUBELET_CONFIG_SHA256"
fi

#cleanup_old_configs
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
