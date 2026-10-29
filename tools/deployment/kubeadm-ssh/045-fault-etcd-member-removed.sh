#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# FAULT INJECTION, not a user scenario nor a step of the lifecycle: the
# recovery of the reconcile from a broken control plane node.
#
# The etcd member of a control plane node is removed as the reconcile does
# with an unhealthy one (kubeadm reset phase remove-etcd-member, the manifest
# removed). Its anchor started again without the kubeadm annotation (the
# reconcile acts only on a configuration it didn't apply) joins the member
# again: the join configuration of the bootstrap script with the admin.conf of
# the node instead of the bootstrap token (rejoin_control_plane of the
# reconcile script).
#
# FAULT_NODE: the control plane node, by default the last one of NODES (not
# the one of kubeadm init, where the gate runs kubectl).

set -exo pipefail

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${NODES:="${WORK_DIR}/nodes.yaml"}"
# the key of the gate (the zuul playbook adds it to all the nodes)
: "${SSH_KEY:="${HOME}/.ssh/kubeadm-gate"}"
: "${NAMESPACE:="kube-system"}"
: "${FAULT_TIMEOUT:="900"}"

SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i ${SSH_KEY}"
CONTROL_PLANE=$(python3 -c '
import sys, yaml
for node in yaml.safe_load(open(sys.argv[1]))["nodes"]:
    if node["role"] == "control-plane":
        print(node["name"], node["ip"])' "${NODES}")
FIRST_NODE=$(head -n 1 <<< "${CONTROL_PLANE}" | cut -d ' ' -f 1)
: "${FAULT_NODE:="$(tail -n 1 <<< "${CONTROL_PLANE}" | cut -d ' ' -f 1)"}"
FAULT_IP=$(awk -v node="${FAULT_NODE}" '$1 == node { print $2 }' <<< "${CONTROL_PLANE}")
test -n "${FAULT_IP}"

# the members of etcd, from the etcd of the first control plane node. The
# apiserver of the faulty node loses its etcd: haproxy closes its sessions
# (exec through the VIP too), so retries
etcd_members() {
  local n
  for n in 1 2 3 4 5 6 7 8 9 10; do
    kubectl -n "${NAMESPACE}" exec "etcd-${FIRST_NODE}" -- etcdctl \
      --endpoints https://127.0.0.1:2379 \
      --cacert /etc/kubernetes/pki/etcd/ca.crt \
      --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
      --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
      member list && return 0
    sleep 5
  done
  return 1
}

# wait_members <count>: until etcd has that many members
wait_members() {
  local end=$(($(date +%s) + FAULT_TIMEOUT))
  until [ "$(etcd_members | wc -l)" -eq "$1" ]; do
    if [ "$(date +%s)" -gt "${end}" ]; then
      echo "Timed out waiting for $1 etcd members" >&2
      return 1
    fi
    sleep 5
  done
  etcd_members
}

MEMBERS=$(etcd_members | wc -l)
etcd_members

# the fault: the etcd member of the node removed
${SSH} "${FAULT_IP}" 'sudo kubeadm reset phase remove-etcd-member && sudo rm -f /etc/kubernetes/manifests/etcd.yaml'
wait_members $((MEMBERS - 1))

# the anchor of the node: a new pass without the kubeadm annotation
kubectl annotate node "${FAULT_NODE}" last-applied-kubeadm-cfg-sha256-
kubectl -n "${NAMESPACE}" delete pod -l component=kubernetes-kubeadm-anchor \
  --field-selector "spec.nodeName=${FAULT_NODE}" --wait=false

# the control plane of the node is ready over a liveness period (10s): its
# apiserver may still be killed for the probes failed without etcd
control_plane_ready() {
  local n ready
  for n in 1 2 3 4; do
    ready=$(kubectl -n "${NAMESPACE}" get pods -l tier=control-plane \
      --field-selector "spec.nodeName=${FAULT_NODE}" \
      -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}') || return 1
    [ -n "${ready}" ] && ! grep -qv '^True$' <<< "${ready}" || return 1
    [ "${n}" -eq 4 ] || sleep 5
  done
}

# the member joins again, the control plane of the node is ready
END=$(($(date +%s) + FAULT_TIMEOUT))
until [ "$(etcd_members | wc -l)" -eq "${MEMBERS}" ] && control_plane_ready; do
  if [ "$(date +%s)" -gt "${END}" ]; then
    echo "Timed out waiting for the etcd member of ${FAULT_NODE}" >&2
    for pod in $(kubectl -n "${NAMESPACE}" get pods -l component=kubernetes-kubeadm-anchor \
        --field-selector "spec.nodeName=${FAULT_NODE}" -o name); do
      kubectl -n "${NAMESPACE}" logs "${pod}" --tail=200 || true
    done
    exit 1
  fi
  etcd_members || true
  sleep 15
done
etcd_members

# the anchor of the node is done
kubectl -n "${NAMESPACE}" rollout status daemonset/kubeadm-service-masters-anchor --timeout="${FAULT_TIMEOUT}s"
kubectl get node "${FAULT_NODE}" -o jsonpath='{.metadata.annotations.last-applied-kubeadm-cfg-sha256}' | grep -q .
