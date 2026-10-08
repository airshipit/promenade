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
# directory where host fs is mounted if we run in the pod
HOST_DIR="${HOST_DIR:-}"

# config directories
KUBERNETES_DIR="/etc/kubernetes"

KUBERNETES_VERSION="$(sed -n 's/^ *kubernetesVersion: *\(.*\)/\1/p' /tmp/allnodes/kubeadm_ClusterConfiguration)"
# if isn't specified - kubeadm uses the version which corresponds to the binary
[ -z "$KUBERNETES_VERSION" ] && KUBERNETES_VERSION=$(kubeadm version -o short)
KUBEADM_ANNOTATION="last-applied-kubeadm-cfg-sha256"
KUBELET_ANNOTATION="last-applied-kubelet-cfg-sha256"
CRI_SOCKET_ANNOTATION="kubeadm.alpha.kubernetes.io/cri-socket"

# Node info
LAST_APPLIED_KUBEADM_CONFIG_SHA256=""
LAST_APPLIED_KUBELET_CONFIG_SHA256=""
CRI_SOCKET=""
KUBELET_CURRENT_VERSION=""
KUBERNETES_ETCD=""

# sleep randomly up to 30 seconds
sleep $(shuf -i 1-30 -n 1)

NODE_INFO=$(kubectl get node $NODE_NAME -o jsonpath="{.metadata.annotations.$KUBEADM_ANNOTATION}|{.metadata.annotations.$KUBELET_ANNOTATION}|{.metadata.annotations.$CRI_SOCKET_ANNOTATION}|{.status.nodeInfo.kubeletVersion}|{.metadata.labels.kubernetes-etcd}")
IFS='|' read -r LAST_APPLIED_KUBEADM_CONFIG_SHA256 LAST_APPLIED_KUBELET_CONFIG_SHA256 CRI_SOCKET KUBELET_CURRENT_VERSION KUBERNETES_ETCD <<<$NODE_INFO

ensure_fs() {
  [ -f "${ROOTFS}/tmp/node.tar" ] && tar -xf "${ROOTFS}/tmp/node.tar" -C "${ROOTFS}/tmp"
}
cleanup_fs() {
  [ -d "${ROOTFS}/tmp/per-node" ] && rm -rf "${ROOTFS}/tmp/per-node"
}

{{/* adding shared bash functions */}}
{{ $sharedLibsContent }}
# end of common functions

cleanup_old_backups() {
  if [ -e "${ROOTFS}${HOST_DIR}/etc/kubernetes/tmp/" ]; then
    for p in kubeadm-backup-etcd kubeadm-backup-manifests; do ls -d "${ROOTFS}${HOST_DIR}/etc/kubernetes/tmp/$p-*" 2>/dev/null | sort | sed '$d' | xargs -r rm -rf || true; done
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
#  remove_if_exists "${HOST_DIR}{{ $file }}"
#{{- end }}
*/}}
#  echo "cleanup_old_configs is done"
#}

restart_kubelet() {
  kubectl drain "${NODE_NAME}" --pod-selector '!kubelet-restart' --ignore-daemonsets --delete-emptydir-data

  # heredoc will take care of ${NODE_NAME} and etc
  job_name=$(kubectl create -f - -o name <<EOF_DATA
{{ tuple $envAll "templates/bin/helpers/_kubelet_restart.yaml.tpl" | include "kubeadm.bundle.template" }}
EOF_DATA
)

  kubectl wait -n kube-system --for=condition=complete $job_name --timeout=600s

  kubectl uncordon "${NODE_NAME}"
  kubectl wait node --for=condition=ready "${NODE_NAME}" --timeout=60s

  sleep 60

  KUBELET_CURRENT_VERSION=$(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
  if [[ $KUBELET_CURRENT_VERSION != $(kubelet --version | awk '{print $2}') ]]; then
    echo "kubelet version mismatch"
    exit 1
  fi

  sleep 60
}

is_action_required() {
  if [[ $NODE_ROLE == "master" ]]; then
    if [ -z $LAST_APPLIED_KUBEADM_CONFIG_SHA256 ]; then return 0; fi
    current_cluster_config_sha256=$(sha256sum < /tmp/allnodes/kubeadm_ClusterConfiguration | cut -d ' ' -f 1)
    if [[ $LAST_APPLIED_KUBEADM_CONFIG_SHA256 != $current_cluster_config_sha256 ]]; then
      return 0
    fi
  fi

{{- if $envAll.Values.kubelet.restart  }}
  if [ -z $LAST_APPLIED_KUBELET_CONFIG_SHA256 ]; then return 0; fi
  current_kubelet_config_sha256=$(sha256sum < /tmp/allnodes/kubelet_config.yaml | cut -d ' ' -f 1)

  if [[ $LAST_APPLIED_KUBELET_CONFIG_SHA256 != $current_kubelet_config_sha256 || $KUBELET_CURRENT_VERSION != $KUBERNETES_VERSION ]]; then
    KUBELET_RESTART_REQUIRED=true
    return 0
  fi
{{- end }}

  return 1
}

annotate_node() {
  kubectl annotate node --overwrite "$NODE_NAME" "$1=$2"
}

kubeadm() {
  if [[ "$1" == "version" ]]; then
    command kubeadm $@
  else
    command kubeadm --rootfs "${ROOTFS}${HOST_DIR}" --v=5 $@
  fi
}

kubeadm_action() {
  if [ -z $CRI_SOCKET ]; then
    annotate_node "$CRI_SOCKET_ANNOTATION" "$(sed -n 's/^ *containerRuntimeEndpoint: *\(.*\)/\1/p' /tmp/allnodes/kubelet_config.yaml)"
  fi

  # switching node to the controller
  if [[ ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" ||
       ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-controller-manager.yaml" ||
       ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-scheduler.yaml"  ]] ||
       [[ $KUBERNETES_ETCD == "enabled" && ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/etcd.yaml" ]]; then
    if ! kubeadm join --config "${KUBERNETES_DIR}/kubeadm/join_config.yaml"; then
      if [[ $KUBERNETES_ETCD == "enabled" ]]; then
        echo "kubeadm join failed, performing reset to clean up local etcd member"
        kubeadm reset phase remove-etcd-member
        rm -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/etcd.yaml" || true
        sleep 30
      fi
      exit 1
    fi
  else
    if ! kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 30s; then
      echo "control plane pods are not healthy, resetting the node"
      if [[ $KUBERNETES_ETCD == "enabled" ]]; then
        if ! kubectl wait --for=condition=ready pod -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l component=etcd --timeout 10s 2>/dev/null; then
          echo "performing reset to clean up local etcd member"
          kubeadm reset phase remove-etcd-member
          rm -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/etcd.yaml" || true
          sleep 30
        fi
      fi
      for component in kube-apiserver kube-controller-manager kube-scheduler; do
        if ! kubectl wait --for=condition=ready pod -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l component=$component --timeout 10s 2>/dev/null; then
          echo "Removing unhealthy static pod manifest for $component"
          rm -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/${component}.yaml"
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

# this is anchor specific - taking it from the image.
sync_binary() {
    local src="$1"
    local dest="$2"

    # if there is no dest or its hash is different - update
    if [[ ! -e "$dest" ]] || ! cmp -s "$src" "$dest"; then
        echo "Updating binary: $dest"
        install -v -b --suffix=-backup "$src" "$(dirname "$dest")/"
        return 0 # exit code 0 means true - file was changed
    fi
    return 1 # exit code 1 means false
}

sync_binaries() {
  local kubelet_restart_needed=1 # exit code 1 means false
  if sync_binary "${ROOTFS}/usr/bin/kubelet" "${ROOTFS}${HOST_DIR}/usr/local/bin/kubelet"; then
    kubelet_restart_needed=0 # exit code 0 - true
    echo "kubelet synced"
  fi

  # actually bins can be installed everywhere
  #if [[ $NODE_ROLE == "master" ]]; then
    sync_binary "${ROOTFS}/usr/bin/kubeadm" "${ROOTFS}${HOST_DIR}/usr/local/bin/kubeadm"
    sync_binary "${ROOTFS}/usr/bin/kubectl" "${ROOTFS}${HOST_DIR}/usr/local/bin/kubectl"
  #fi
  return $kubelet_restart_needed
}

# migrate from airship names
rename_cp_pods() {
  cp_pods="etcd apiserver controller-manager scheduler"
  for cp_pod in $cp_pods; do
    src_path="${HOST_DIR}${KUBERNETES_DIR}/manifests/kubernetes-${cp_pod}.yaml"
    dst_path="${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-${cp_pod}.yaml"
    component="kube-${cp_pod}"
    if [[ $cp_pod == "etcd" ]]; then
      dst_path="${HOST_DIR}${KUBERNETES_DIR}/manifests/${cp_pod}.yaml"
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

if [[ $(kubeadm version -o short) != "$KUBERNETES_VERSION" ]]; then
  echo "Desired kubernetes version mismatch with provided binaries version, please update kubernetes version in values to $(kubeadm version -o short)"
  exit 1
fi

cleanup_old_backups

KUBELET_RESTART_REQUIRED=false

ensure_fs

sync_kubeconfigs
sync_kubelet && KUBELET_RESTART_REQUIRED={{ $envAll.Values.kubelet.restart  }}
sync_binaries && $KUBELET_RESTART_REQUIRED={{ $envAll.Values.kubelet.restart  }}

# migration from Airship to kubeadm
# kubeadm mutates the kubeconfig passed via --kubeconfig if it is a default one
# (/etc/kubernetes/admin.conf). Operate on a throwaway copy of admin.conf so the
# synced /etc/kubernetes/admin.conf on the host is not modified.
# (TODO) move this check prior to kubeadm join command, as well add a check if kubeconfig
# has been modified due to cert rotation
if [ $NODE_ROLE == "master" ] && ! kubectl get cm -n kube-public cluster-info; then
  tmp_admin_conf="$(mktemp -p "$HOST_DIR/tmp/" -t temp-kubeconfig.XXXXXX)"
  cp "$HOST_DIR/etc/kubernetes/admin.conf" "$tmp_admin_conf"
  rc=0
  kubeadm init phase bootstrap-token --kubeconfig "${tmp_admin_conf#$HOST_DIR}" || rc=$?
  rm -f "$tmp_admin_conf"
  [ $rc -eq 0 ] || exit $rc
fi

# migration from Airship to kubeadm
[[ $NODE_ROLE == "master" ]] && rename_cp_pods

# stranged but original script had this after
sync_certs
sync_kubeadm

# by default etcd is disabled - but if it was installed - turn this phase onn
if [[ $KUBERNETES_ETCD == "enabled" ]]; then
  # do not skip etcd related phases
  [ -f "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/join_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
  [ -f "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/init_config.yaml" ] && sed "${SED_INPLACE[@]}" '/check-etcd\|etcd-join/d' "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/init_config.yaml" #TODO: to verify
  # turn on etcd upgrade
  [ -f "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml" ] && sed "${SED_INPLACE[@]}" -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
fi

if [[ $NODE_ROLE == "master" ]] && is_action_required; then
  kubeadm_action
  LAST_APPLIED_KUBEADM_CONFIG_SHA256="$(sha256sum < /tmp/allnodes/kubeadm_ClusterConfiguration | cut -d ' ' -f 1)"
  annotate_node "$KUBEADM_ANNOTATION" "$LAST_APPLIED_KUBEADM_CONFIG_SHA256"
fi

if [[ $KUBELET_RESTART_REQUIRED == true ]]; then
  restart_kubelet
  LAST_APPLIED_KUBELET_CONFIG_SHA256="$(sha256sum < /tmp/allnodes/kubelet_config.yaml | cut -d ' ' -f 1)"
  annotate_node "$KUBELET_ANNOTATION" "$LAST_APPLIED_KUBELET_CONFIG_SHA256"
fi

#cleanup_old_configs

touch /tmp/done

# main loop
while true; do
  if [ -e /tmp/stop ] || is_action_required; then
    echo "Stopping"
    break
  fi
  sleep 30
done
