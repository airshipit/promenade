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

# The control plane is lost and restored from an etcd snapshot: ssh-bootstrap.sh
# --restore of the chart (charts/kubeadm/overrides/reference/orchestration-ssh-ca.yaml).
#
# A snapshot of etcd is taken between two ConfigMaps, then all the control
# plane nodes are reset (kubeadm reset without removing their etcd members)
# and their etcd data is lost. The tool bootstraps them again with the same
# PKI: kubeadm init on the first one with the etcd of the snapshot
# (etcd_restore of the bootstrap script), the other ones join it. The workers are untouched, they reconnect.
# The cluster has the ConfigMap created before the snapshot, not the one
# created after it.

set -exo pipefail

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${KUBEADM_CHART:="./charts/kubeadm"}"
: "${NODES:="${WORK_DIR}/nodes.yaml"}"
# the Kubernetes version till day 2
: "${DAY1_VALUES:="./tools/deployment/kubeadm/day1/version.yaml"}"
: "${HELM:="helm"}"
: "${VALUES:="${KUBEADM_CHART}/overrides/reference/orchestration-ssh-ca.yaml"}"
# the key of the gate (the zuul playbook adds it to all the nodes)
: "${SSH_KEY:="${HOME}/.ssh/kubeadm-gate"}"
: "${NAMESPACE:="kube-system"}"
# the snapshot on the first control plane node, out of the data dir of etcd
# (kubeadm reset empties it)
: "${SNAPSHOT:="/var/lib/etcd-gate-snapshot.db"}"

export HELM
export CHART_ARGS="kubeadm ${KUBEADM_CHART} -f ${VALUES} -f ${NODES} -f ${DAY1_VALUES}"
# the PKI of day 0: the nodes come back with it
export PKI_VALUES="${WORK_DIR}/pki-values.yaml"
export SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i ${SSH_KEY}"
test -s "${PKI_VALUES}"

CONTROL_PLANE=$(python3 -c '
import sys, yaml
for node in yaml.safe_load(open(sys.argv[1]))["nodes"]:
    if node["role"] == "control-plane":
        print(node["name"], node["ip"])' "${NODES}")
FIRST_NODE=$(head -n 1 <<< "${CONTROL_PLANE}" | cut -d ' ' -f 1)
FIRST_IP=$(head -n 1 <<< "${CONTROL_PLANE}" | cut -d ' ' -f 2)
MEMBERS=$(wc -l <<< "${CONTROL_PLANE}")

etcdctl() {
  kubectl -n "${NAMESPACE}" exec "etcd-${FIRST_NODE}" -- etcdctl \
    --endpoints https://127.0.0.1:2379 \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
    --key /etc/kubernetes/pki/etcd/healthcheck-client.key "$@"
}

# the snapshot between the two ConfigMaps
kubectl -n default create configmap etcd-restore-before --from-literal=step=before
etcdctl snapshot save /var/lib/etcd/gate-snapshot.db
${SSH} "${FIRST_IP}" "sudo mv /var/lib/etcd/gate-snapshot.db ${SNAPSHOT}"
kubectl -n default create configmap etcd-restore-after --from-literal=step=after

# the control plane is lost: kubeadm reset empties the etcd data dir only in
# the skipped phase, so the data is removed here
while read -r _ ip; do
  ${SSH} "${ip}" 'sudo kubeadm reset -f --skip-phases=remove-etcd-member && sudo rm -rf /var/lib/etcd' < /dev/null
done <<< "${CONTROL_PLANE}"

# shellcheck disable=SC2086 # CHART_ARGS is a list of arguments
${HELM} template ${CHART_ARGS} \
  --set manifests.secret_tools=true --set entrypoint.default=null \
  | sed -n 's/^ *ssh-bootstrap.sh: *\(.*\)/\1/p' | base64 -d > "${WORK_DIR}/ssh-bootstrap.sh"
test -s "${WORK_DIR}/ssh-bootstrap.sh"
bash "${WORK_DIR}/ssh-bootstrap.sh" --restore "${SNAPSHOT}"
${SSH} "${FIRST_IP}" "sudo rm -f ${SNAPSHOT}"

# kubeadm init wrote a new admin.conf
( umask 077; sudo kubectl --kubeconfig /etc/kubernetes/admin.conf config view --raw --flatten > "${HOME}/.kube/config" )

# the nodes and the anchors are back, etcd has all the members and the state
# of the snapshot
kubectl wait --for=condition=Ready node --all --timeout=600s
kubectl -n "${NAMESPACE}" rollout status daemonset/kubeadm-service-masters-anchor --timeout=900s
kubectl -n "${NAMESPACE}" rollout status daemonset/kubeadm-service-workers-anchor --timeout=900s
etcdctl member list
test "$(etcdctl member list | wc -l)" -eq "${MEMBERS}"
kubectl -n default get configmap etcd-restore-before
if kubectl -n default get configmap etcd-restore-after; then
  echo "the ConfigMap created after the snapshot is there: etcd isn't restored" >&2
  exit 1
fi
kubectl -n default delete configmap etcd-restore-before
kubectl get nodes -o wide
