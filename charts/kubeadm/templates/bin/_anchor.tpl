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

# directories
HOST_DIR="{{ .Values.host_dir }}"
KUBERNETES_DIR="/etc/kubernetes"
CERT_DIR="${HOST_DIR}${KUBERNETES_DIR}/pki"

# flow controls
STATIC_PODS_RESTART_REQUIRED=false
KUBELET_RESTART_REQUIRED=false

KUBERNETES_VERSION="{{ .Values.cluster_config.kubernetesVersion }}"
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

kubeadm() {
  if [[ "$1" == "version" ]]; then
    command kubeadm $@
  else
    command kubeadm --rootfs "$HOST_DIR" --v=5 $@
  fi
}

annotate_node() {
  kubectl annotate node --overwrite "$NODE_NAME" "$1=$2"
}

sync_configs() {
  sync_kubeconfigs
  sync_kubelet_configs
  sync_binaries

  if [[ $NODE_ROLE == "master" ]]; then
    rename_cp_pods
    sync_control_plane_certs
    sync_etcd_certs
    sync_apiserver_misc_configs
    sync_kubeadm_configs
    sync_patches
  fi
}

compare_copy_file() {
  src=$1
  delete_src=false
  if [ ! -f "$1" ]; then
    src=$(mktemp)
    cat - > $src
    delete_src=true
  fi
  dst=$2

  if [ ! -e "${dst}" ] || ! cmp -s $src $dst; then
    [[ -d "$(dirname ${dst})" ]] || mkdir -p $(dirname "${dst}")
    chmod a+r $(dirname "${dst}")

    cp "${src}" "${dst}"
    chmod a+r "${dst}"

    if [[ "${dst}" == /etc/kubernetes/pki/* ]]; then
      echo "Certificates change detected, static pods will be restarted"
      #STATIC_PODS_RESTART_REQUIRED=true
    fi

{{- if .Values.kubelet.restart }}
    if [[ "${dst}" == "${HOST_DIR}/etc/default/kubelet" ||
          "${dst}" == "${HOST_DIR}/etc/systemd/system/kubelet.service" ||
          "${dst}" == "${HOST_DIR}/var/lib/kubelet/config.yaml" ]]; then
      KUBELET_RESTART_REQUIRED=true
    fi
{{- end }}

  fi

  if [[ $delete_src == true ]]; then
    rm $src
  fi
}

rename_cp_pods() {
  cp_pods="etcd apiserver controller-manager scheduler"
  for cp_pod in $cp_pods; do
    src_path="${HOST_DIR}${KUBERNETES_DIR}/manifests/kubernetes-${cp_pod}.yaml"
    if [ -e "$src_path" ]; then
      dst_path="${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-${cp_pod}.yaml"
      component="kube-${cp_pod}"
      if [[ $cp_pod == "etcd" ]]; then
        dst_path="${HOST_DIR}${KUBERNETES_DIR}/manifests/${cp_pod}.yaml"
        component="${cp_pod}"
      fi

      if [ $(kubectl get pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l component=$component --no-headers | wc -l) -gt 0 ]; then
        kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l component=$component --timeout=180s
      fi
      cp "$src_path" "$dst_path"
      rm "$src_path"
      sed -i -e "s/name: kubernetes-$cp_pod/name: $component/g" "$dst_path"
      sleep 30
      kubectl wait --for=condition=ready pod -n kube-system --field-selector spec.nodeName=$NODE_NAME -l component=$component --timeout=180s
    fi
  done
}

remove_if_exists() {
  path="$1"
  if [ -e "$path" ]; then
    if [ -d "$path" ]; then rm -rf $path; else rm -f "$path"; fi
  fi
}

sync_kubeconfigs() {
  cluster_ip="{{ .Values.kubeconfig.cluster_ip }}"
  cluster_port="{{ .Values.kubeconfig.cluster_port }}"
  cluster_name="{{ .Values.kubeconfig.cluster_name }}"
  {{ range $name, $data := .Values.kubeconfig.configs }}
  if [[ "{{ $name }}" == "kubelet" || $NODE_ROLE == "master" ]]; then
    CLUSTER_IP="$cluster_ip" CLUSTER_PORT="$cluster_port" \
      CERT_AUTH="{{ $data.ca }}" CLUSTER_NAME="$cluster_name" USER="{{ $name }}" \
      CLIENT_CERT="{{ $data.client_cert }}" CLIENT_KEY="{{ $data.client_key }}" \
      envsubst < /tmp/kubeconfig/kubeconfig.yaml.tpl | compare_copy_file - "$HOST_DIR{{ $data.path }}"
  fi
  {{- end }}

  if [ $NODE_ROLE == "master" ] && ! kubectl get cm -n kube-public cluster-info; then
    kubeadm init phase bootstrap-token --kubeconfig /etc/kubernetes/admin.conf # move to prior join check
  fi

  echo "kubeconfigs are synced"
}

sync_control_plane_certs() {
  for file in /tmp/certs/*; do
    file_name="$(basename $file)"
    compare_copy_file "$file" "$CERT_DIR/$file_name"
  done
}

sync_kubelet_certs() {
  echo "placeholder"
}

sync_etcd_certs() {
    compare_copy_file /tmp/etcd-certs/ca.crt "$CERT_DIR/etcd/ca.crt"
    compare_copy_file /tmp/etcd-certs/healthcheck-client.crt "$CERT_DIR/etcd/healthcheck-client.crt"
    compare_copy_file /tmp/etcd-certs/healthcheck-client.key "$CERT_DIR/etcd/healthcheck-client.key"

    if [[ $KUBERNETES_ETCD == "enabled" ]]; then
      compare_copy_file /tmp/etcd-certs/ca-peer.crt "$CERT_DIR/etcd/ca-peer.crt"

      compare_copy_file "/tmp/etcd-certs/${NODE_NAME}-peer.crt" "$CERT_DIR/etcd/peer.crt"
      compare_copy_file "/tmp/etcd-certs/${NODE_NAME}-peer.key" "$CERT_DIR/etcd/peer.key"

      compare_copy_file "/tmp/etcd-certs/${NODE_NAME}-server.crt" "$CERT_DIR/etcd/server.crt"
      compare_copy_file "/tmp/etcd-certs/${NODE_NAME}-server.key" "$CERT_DIR/etcd/server.key"
    fi
}

sync_patches() {
  for file in /tmp/patches/*; do
    compare_copy_file "$file" "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/patches/$(basename $file)"
  done
}

sync_apiserver_misc_configs() {
  if [[ $NODE_ROLE == "master" ]]; then
    for file in /tmp/apiserver-misc/*; do
      compare_copy_file "$file" "${HOST_DIR}${KUBERNETES_DIR}/apiserver/$(basename $file)"
    done
  fi
}

sync_kubelet_configs() {
  envsubst < /tmp/kubelet/default-kubelet | compare_copy_file - "${HOST_DIR}/etc/default/kubelet"
  compare_copy_file /tmp/kubelet/kubelet.service "${HOST_DIR}/etc/systemd/system/kubelet.service"
  compare_copy_file /tmp/kubelet/kubelet "${HOST_DIR}/var/lib/kubelet/config.yaml"
}

sync_kubeadm_configs() {
  envsubst < /tmp/kubeadm/join-config.yaml | compare_copy_file - "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
  envsubst < /tmp/kubeadm/upgrade-config.yaml | compare_copy_file - "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"

  if [[ $KUBERNETES_ETCD == "enabled" ]]; then
    # do not skip etcd related phases
    sed -i '/check-etcd\|etcd-join/d' "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
    # turn on etcd upgrade
    sed -i -e 's/etcdUpgrade: false/etcdUpgrade: true/g' "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
  fi
}

sync_binaries() {
  #envsubst < "/tmp/bin/kubelet_restart.sh" | compare_copy_file - "$HOST_DIR/usr/local/bin/kubelet_restart.sh"
  #chmod a+x "$HOST_DIR/usr/local/bin/kubelet_restart.sh"

  if [[ ! -e "$HOST_DIR/usr/local/bin/kubelet" || $(kubelet --version) != $($HOST_DIR/usr/local/bin/kubelet --version) ]]; then
{{- if .Values.kubelet.restart }}
    KUBELET_RESTART_REQUIRED=true
{{- end }}

    install -v -b --suffix=-backup /usr/bin/kubelet $HOST_DIR/usr/local/bin/
  fi

  if [[ $NODE_ROLE == "master" ]]; then
    if [[ ! -e "$HOST_DIR/usr/local/bin/kubeadm" || "$(kubeadm version -o short)" != "$($HOST_DIR/usr/local/bin/kubeadm version -o short)" ]]; then
      install -v -b --suffix=-backup /usr/bin/kubeadm $HOST_DIR/usr/local/bin/
    fi

    if [[ ! -e "$HOST_DIR/usr/local/bin/kubectl" || $(kubectl version --client | grep Client) != $($HOST_DIR/usr/local/bin/kubectl version --client | grep Client) ]]; then
      install -v -b --suffix=-backup /usr/bin/kubectl $HOST_DIR/usr/local/bin/
    fi
  fi
}

cleanup_old_configs() {
{{- range $file := .Values.const.files_to_delete }}
  remove_if_exists "${HOST_DIR}{{ $file }}"
{{- end }}
}

restart_kubelet() {
  # kubelet_restart.yaml has to be renamed to node_action.yaml
  kubectl drain "${NODE_NAME}" --pod-selector '!kubelet-restart' --ignore-daemonsets --delete-emptydir-data
  job_name=$(envsubst < "/tmp/jobs/kubelet_restart.yaml.tpl" | kubectl create -f - | grep created | awk '{print $1}')
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
    current_cluster_config_sha256=$(sha256sum < /tmp/kubeadm/ClusterConfiguration | cut -d ' ' -f 1)
    if [[ $LAST_APPLIED_KUBEADM_CONFIG_SHA256 != $current_cluster_config_sha256 ]]; then
      return 0
    fi
  fi

{{- if .Values.kubelet.restart }}
  if [ -z $LAST_APPLIED_KUBELET_CONFIG_SHA256 ]; then return 0; fi
  current_kubelet_config_sha256=$(sha256sum < /tmp/kubelet/kubelet | cut -d ' ' -f 1)

  if [[ $LAST_APPLIED_KUBELET_CONFIG_SHA256 != $current_kubelet_config_sha256 || $KUBELET_CURRENT_VERSION != $KUBERNETES_VERSION ]]; then
    KUBELET_RESTART_REQUIRED=true
    return 0
  fi
{{- end }}

  return 1
}

verlte() {
    printf '%s\n' "$1" "$2" | sort -C -V
}

verlt() {
    ! verlte "$2" "$1"
}

kubeadm_action() {
  if [ -z $CRI_SOCKET ]; then
    annotate_node "$CRI_SOCKET_ANNOTATION" "{{ .Values.kubelet.config.containerRuntimeEndpoint }}"
  fi

  if [[ ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" ||
       ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-controller-manager.yaml" ||
       ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-scheduler.yaml"  ]] ||
       [[ $KUBERNETES_ETCD == "enabled" && ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/etcd.yaml" ]]; then
    kubeadm join --config "${KUBERNETES_DIR}/kubeadm/join_config.yaml"
  else
    if [ $(kubectl get pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l tier=control-plane --no-headers | wc -l) -gt 0 ]; then
      kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName!=$NODE_NAME" -l tier=control-plane --timeout 300s
    fi
    kubeadm upgrade node --config "${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
    sync_kubeconfigs
    kubectl wait --for=condition=ready pods -n kube-system --field-selector "spec.nodeName=$NODE_NAME" -l tier=control-plane --timeout 300s
  fi
}

if [[ $(kubeadm version -o short) != "$KUBERNETES_VERSION" ]]; then
  echo "Desired kubernetes version mismatch with provided binaries version, please update kubernetes version in values to $(kubeadm version -o short)"
  exit 1
fi

sync_configs

if [[ $NODE_ROLE == "master" ]] && is_action_required; then
  kubeadm_action
  LAST_APPLIED_KUBEADM_CONFIG_SHA256="$(sha256sum < /tmp/kubeadm/ClusterConfiguration | cut -d ' ' -f 1)"
  annotate_node "$KUBEADM_ANNOTATION" "$LAST_APPLIED_KUBEADM_CONFIG_SHA256"
fi

if [[ $KUBELET_RESTART_REQUIRED == true ]]; then
  restart_kubelet
  LAST_APPLIED_KUBELET_CONFIG_SHA256="$(sha256sum < /tmp/kubelet/kubelet | cut -d ' ' -f 1)"
  annotate_node "$KUBELET_ANNOTATION" "$LAST_APPLIED_KUBELET_CONFIG_SHA256"
fi

cleanup_old_configs

touch /tmp/done

# main loop
while true; do
  if [ -e /tmp/stop ] || is_action_required; then
    echo "Stopping"
    break
  fi
  sleep 30
done
