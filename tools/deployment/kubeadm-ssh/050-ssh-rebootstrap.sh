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

# Abrupt rotation of the PKI over ssh: the ssh-rebootstrap.sh tool of the chart
# (charts/kubeadm/overrides/reference/ssh-orchestration-<ORCHESTRATION>.yaml)
# puts a new PKI on all the nodes of the gate from this node, the workloads are
# restarted:
# - ca: new CAs and service account key (gen-pki.sh of the chart), kubeadm
#   generates its certificates again, the workers go through the TLS bootstrap
#   of kubelet again
# - full: all the certificates new (gen-pki-full.sh of the orchestration)
#
# The reconcile waits meanwhile (the lock of the rebootstrap): the chart in the
# cluster gets the new PKI (the catalog of 035-generate-catalog.sh, as helm
# upgrade would do) before the lock is released.
#
# API_DOWN=true: the apiservers are stopped first (as with an expired CA, the
# API doesn't work), the rebootstrap mustn't need the API until the control
# plane nodes restart with the new CAs.

set -exo pipefail

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${KUBEADM_CHART:="./charts/kubeadm"}"
: "${NODES:="${WORK_DIR}/nodes.yaml"}"
# the Kubernetes version till day 2
: "${DAY1_VALUES:="./tools/deployment/kubeadm/day1/version.yaml"}"
: "${CATALOG:="${WORK_DIR}/catalog"}"
: "${HELM:="helm"}"
# the reference orchestration: ca or full
: "${ORCHESTRATION:="ca"}"
# the values of the cluster: the reference orchestration
: "${VALUES:="${KUBEADM_CHART}/overrides/reference/ssh-orchestration-${ORCHESTRATION}.yaml"}"
# the key of the gate (the zuul playbook adds it to all the nodes)
: "${SSH_KEY:="${HOME}/.ssh/kubeadm-gate"}"
: "${API_DOWN:="false"}"

export HELM
export SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i ${SSH_KEY}"
CLUSTER_ARGS="kubeadm ${KUBEADM_CHART} -f ${VALUES} -f ${NODES} -f ${DAY1_VALUES}"
PKI_TOOL=gen-pki.sh
[ "${ORCHESTRATION}" != full ] || PKI_TOOL=gen-pki-full.sh

# the new PKI, only the tools are rendered (entrypoint.default is off)
rm -f "${WORK_DIR}/pki-values-rotated.yaml"
# shellcheck disable=SC2086 # CLUSTER_ARGS is a list of arguments
${HELM} template ${CLUSTER_ARGS} \
  --set manifests.secret_tools=true --set entrypoint.default=null \
  | sed -n "s/^ *${PKI_TOOL}: *\(.*\)/\1/p" | base64 -d \
  | bash -s -- --out-file "${WORK_DIR}/pki-values-rotated.yaml"
test -s "${WORK_DIR}/pki-values-rotated.yaml"
export CHART_ARGS="${CLUSTER_ARGS} -f ${WORK_DIR}/pki-values-rotated.yaml"

# shellcheck disable=SC2086 # CHART_ARGS is a list of arguments
${HELM} template ${CHART_ARGS} \
  --set manifests.secret_tools=true --set entrypoint.default=null \
  | sed -n 's/^ *ssh-rebootstrap.sh: *\(.*\)/\1/p' | base64 -d > "${WORK_DIR}/ssh-rebootstrap.sh"
test -s "${WORK_DIR}/ssh-rebootstrap.sh"

CA_BEFORE=$(sudo sha256sum /etc/kubernetes/pki/ca.crt | cut -d ' ' -f 1)

# kubelet stopped first: it doesn't start the apiservers again
if [ "${API_DOWN}" = "true" ]; then
  for ip in $(python3 -c '
import sys, yaml
for node in yaml.safe_load(open(sys.argv[1]))["nodes"]:
    if node["role"] == "control-plane":
        print(node["ip"])' "${NODES}"); do
    ${SSH} "${ip}" 'sudo systemctl stop kubelet &&
      sudo crictl stopp $(sudo crictl pods -q --namespace kube-system --label component=kube-apiserver)'
  done
  if kubectl get --raw /livez --request-timeout=10s; then
    echo "the API is still up" >&2
    exit 1
  fi
fi

bash "${WORK_DIR}/ssh-rebootstrap.sh" --restart-clients
test "$(sudo sha256sum /etc/kubernetes/pki/ca.crt | cut -d ' ' -f 1)" != "${CA_BEFORE}"

# the admin of the new CA, the credentials embedded
( umask 077; sudo kubectl --kubeconfig /etc/kubernetes/admin.conf config view --raw --flatten > "${HOME}/.kube/config" )
kubectl get nodes -o wide

# the chart in the cluster with the new PKI, then the lock is released
mv "${WORK_DIR}/pki-values.yaml" "${WORK_DIR}/pki-values-old.yaml"
mv "${WORK_DIR}/pki-values-rotated.yaml" "${WORK_DIR}/pki-values.yaml"
export CHART_ARGS="${CLUSTER_ARGS} -f ${WORK_DIR}/pki-values.yaml"
./tools/deployment/kubeadm/035-generate-catalog.sh
kubectl apply -k "${CATALOG}/kubeadm" --server-side --force-conflicts
bash "${WORK_DIR}/ssh-rebootstrap.sh" --phases backup-remove

kubectl wait --for=condition=Ready nodes --all --timeout=300s
# all the static pods restarted at once with the new PKI: etcd and the
# apiservers take a while to be ready again
kubectl -n kube-system wait --for=condition=Ready pod -l tier=control-plane --timeout=300s
