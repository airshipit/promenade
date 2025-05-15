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
READY_TO_START=false
FIRST_POD=false # remove
KUBEADM_ACTION_REQUIRED=$([ $NODE_ROLE == "master" ] && echo "true" || echo "false")
KUBELET_RESTART_REQUIRED=false

KUBERNETES_VERSION="{{ .Values.kubeadm.cluster_config.kubernetesVersion }}"
KUBEADM_ANNOTATION="last-applied-kubeadm-cfg-sha256"
KUBELET_ANNOTATION="last-applied-kubelet-cfg-sha256"

LAST_APPLIED_KUBEADM_CONFIG_SHA256=$([ $NODE_ROLE == "master" ] && kubectl get node $NODE_NAME -o jsonpath="{.metadata.annotations.$KUBEADM_ANNOTATION}" || echo "")
LAST_APPLIED_KUBELET_CONFIG_SHA256=$(kubectl get node $NODE_NAME -o jsonpath="{.metadata.annotations.$KUBELET_ANNOTATION}")

# substitute from values
MASTERS_DS_NAME="{{ .Values.service.name }}-masters-anchor"
WORKERS_DS_NAME="{{ .Values.service.name }}-workers-anchor"
CURRENT_DS_NAME=$([ $NODE_ROLE == "master" ] && echo "$MASTERS_DS_NAME" || echo "$WORKERS_DS_NAME")

MASTERS_POD_LABELS="component=kubernetes-kubeadm-anchor"
WORKERS_POD_LABELS="component=kubernetes-kubeadm-workers-anchor"
CURRENT_POD_LABELS=$([ $NODE_ROLE == "master" ] && echo "$MASTERS_POD_LABELS" || echo "$WORKERS_POD_LABELS")

kubeadm() {
  $(which kubeadm) --rootfs "$HOST_DIR" --v=5 $@
}

annotate_node() {
  kubectl annotate node --overwrite "$NODE_NAME" "$1=$2"
}

sync_configs() {
  sync_kubeconfigs
  sync_kubelet_configs
  sync_binaries

  if [[ $NODE_ROLE == "master" ]]; then
    sync_control_plane_certs
    sync_apiserver_misc_configs
    sync_kubeadm_configs
    sync_patches
  fi

  cleanup_old_configs
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

move_if_exists() {
  path="$1"
  move_to="$2"

  if [ -e "$path" ]; then mv "$path" "$move_to"; fi
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
    kubeadm init phase bootstrap-token --kubeconfig /etc/kubernetes/admin.conf
  fi

  echo "kubeconfigs are synced"
}

sync_control_plane_certs() {
  if [[ $NODE_ROLE != "master" ]]; then return; fi
  for file in /tmp/certs/*; do
    file_name="$(basename $file)"
    if [[ "$file_name" == etcd-* ]]; then
      compare_copy_file "$file" "$CERT_DIR/etcd/${file_name/etcd-/}"
    else
      compare_copy_file "$file" "$CERT_DIR/$file_name"
    fi
  done
}

sync_kubelet_certs() {
  echo "placeholder"
}

sync_etcd_certs() {
  echo "placeholder"
}

sync_patches() {
  #remove_if_exists "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/patches/"
  if [[ $NODE_ROLE != "master" ]]; then return; fi
  for file in /tmp/patches/*; do
    compare_copy_file "$file" "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/patches/$(basename $file)"
  done
}

sync_apiserver_misc_configs() {
  if [[ $NODE_ROLE == "master" ]]; then
    for file in /tmp/apiserver-misc/*; do
      compare_copy_file  "$file" "${HOST_DIR}${KUBERNETES_DIR}/apiserver/$(basename $file)"
    done
  fi
}

sync_kubelet_configs() {
  envsubst < /tmp/kubelet/default-kubelet | compare_copy_file - "${HOST_DIR}/etc/default/kubelet"
  compare_copy_file /tmp/kubelet/kubelet.service "${HOST_DIR}/etc/systemd/system/kubelet.service"
  compare_copy_file /tmp/kubelet/kubelet "${HOST_DIR}/var/lib/kubelet/config.yaml"
}

sync_kubeadm_configs() {
  #ETCD_ENABLED=$(kubectl get nodes -l kubernetes-etcd=enabled --no-headers -o custom-columns=":metadata.name" | grep -q "$NODE_NAME" && echo "true" || echo "false")
  envsubst < /tmp/kubeadm/join-config.yaml | compare_copy_file - "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/join_config.yaml"
  envsubst < /tmp/kubeadm/upgrade-config.yaml | compare_copy_file - "${HOST_DIR}${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
}

sync_binaries() {
  envsubst < "/tmp/bin/kubelet_restart.sh" | compare_copy_file - "$HOST_DIR/usr/local/bin/kubelet_restart.sh"
  chmod a+x "$HOST_DIR/usr/local/bin/kubelet_restart.sh"

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

# to remove
ready_to_start() {
  pod_list=$(kubectl get pods -n kube-system -l $CURRENT_POD_LABELS --sort-by=.metadata.creationTimestamp --no-headers -o custom-columns=":metadata.name")
  for pod in $pod_list; do
    if [ $pod == $POD_NAME ]; then
      READY_TO_START="true"
      break
    fi

    if ! kubectl wait --for=condition=ready pod -n kube-system $pod --timeout=0; then
      break
    fi
  done
}

daemonset_status() {
  if [[ $NODE_ROLE == "worker" ]] && ! kubectl rollout status "ds/$MASTERS_DS_NAME" -n kube-system -w=false | grep -q "successfully rolled out"; then
    echo "waiting for masters nodes to be ready..."
    return
  fi

  generation=0
  observed_generation=0
  updated_number_scheduled=0
  desired_number_scheduled=0
  number_available=0

  read -r generation observed_generation updated_number_scheduled desired_number_scheduled number_available <<<$(kubectl get ds -n kube-system "$CURRENT_DS_NAME" -o jsonpath='{ .metadata.generation } { .status.observedGeneration } { .status.updatedNumberScheduled } { .status.desiredNumberScheduled } { .status.numberAvailable }')
  while [ $generation -gt $observed_generation ]; do
    echo "Waiting for daemon set spec update to be observed..."
    read -r generation observed_generation updated_number_scheduled desired_number_scheduled number_available <<<$(kubectl get ds -n kube-system "$CURRENT_DS_NAME" -o jsonpath='{ .metadata.generation } { .status.observedGeneration } { .status.updatedNumberScheduled } { .status.desiredNumberScheduled } { .status.numberAvailable }')
    sleep 5
  done

  if [ -z $number_available ]; then
    number_available=0
  fi

	if [ $updated_number_scheduled -lt $desired_number_scheduled ]; then
		echo "Waiting for daemon set rollout to finish: ${updated_number_scheduled} out of ${desired_number_scheduled} new pods have been updated..."
	  # add verification that the pod has to be single (unready)
	  READY_TO_START="true"
	  if [ $updated_number_scheduled -eq 1 ]; then
	    echo "first in sequence"
	    FIRST_POD=true
	  fi
	elif [ $number_available -lt $desired_number_scheduled ]; then
		echo "Waiting for daemon set rollout to finish: ${number_available} of ${desired_number_scheduled} updated pods are available..."
	  if [[ $(($desired_number_scheduled-$number_available)) -eq 1 ]]; then
	    READY_TO_START="true"
	  else
	    ready_to_start
	  fi
	else
		echo "Daemon set successfully rolled out"
		READY_TO_START="true"
		KUBEADM_ACTION_REQUIRED=false
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

  if [[ $(kubectl get node "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.kubeletVersion}') != $(kubelet --version | awk '{print $2}') ]]; then
    echo "kubelet version mismatch"
    exit 1
  fi

  sleep 60
}

is_upgrade_required() {
  IFS='|' read -r last_cluster_config_sha256 last_kubelet_config_sha256 kubelet_current_version <<<$(kubectl get node $NODE_NAME -o jsonpath="{.metadata.annotations.$KUBEADM_ANNOTATION}|{.metadata.annotations.$KUBELET_ANNOTATION}|{.status.nodeInfo.kubeletVersion}")

  if [[ $NODE_ROLE == "master" ]]; then
    if [ -z $last_cluster_config_sha256 ]; then return 0; fi
    current_cluster_config_sha256=$(sha256sum < /tmp/kubeadm/ClusterConfiguration | cut -d ' ' -f 1)
    if [[ $last_cluster_config_sha256 != $current_cluster_config_sha256 ]]; then
      return 0
    fi
  fi

{{- if .Values.kubelet.restart }}
  if [ -z $last_kubelet_config_sha256 ]; then return 0; fi
  current_kubelet_config_sha256=$(sha256sum < /tmp/kubelet/kubelet | cut -d ' ' -f 1)

  if [[ $last_kubelet_config_sha256 != $current_kubelet_config_sha256 || $kubelet_current_version != $KUBERNETES_VERSION ]]; then
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
  if is_upgrade_required; then
   if [[ ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-apiserver.yaml" ||
         ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-controller-manager.yaml" ||
         ! -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-scheduler.yaml"  ]]; then
     rm -f "${HOST_DIR}${KUBERNETES_DIR}/manifests/kube-*" || true
     kubeadm join --config "${KUBERNETES_DIR}/kubeadm/join_config.yaml"
   else
     kubeadm upgrade node --config "${KUBERNETES_DIR}/kubeadm/upgrade_config.yaml"
     sync_kubeconfigs
   fi
  fi
}

rollout_restart() {
  if kubectl rollout status "ds/$CURRENT_DS_NAME" -n kube-system -w=false | grep -q "successfully rolled out"; then
    kubectl rollout restart "ds/$CURRENT_DS_NAME" -n kube-system
  fi
}

while [[ $READY_TO_START != true ]]; do
  daemonset_status
  sleep 5
done

sync_configs

if [[ $(kubeadm version -o short) != "$KUBERNETES_VERSION" ]]; then
  echo "Desired kubernetes version mismatch with provided binaries version, please update kubernetes version in values to $(kubeadm version -o short)"
  exit 1
fi

if [[ $KUBEADM_ACTION_REQUIRED == true ]]; then
  kubeadm_action
  annotate_node "$KUBEADM_ANNOTATION" "$(sha256sum < /tmp/kubeadm/ClusterConfiguration | cut -d ' ' -f 1)"
fi

if [[ $KUBELET_RESTART_REQUIRED == true ]]; then
  restart_kubelet
  annotate_node "$KUBELET_ANNOTATION" "$(sha256sum < /tmp/kubelet/kubelet | cut -d ' ' -f 1)"
fi

touch /tmp/done

# main loop
while true; do
  if [ -e /tmp/stop ] || is_upgrade_required; then
    echo "Stopping"
    rollout_restart
    break
  fi
  sleep 15
done
