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

# Day 0: build the cluster with the bootstrap script of the kubeadm chart.
#
# The chart is rendered with `helm template` from the gate values and the CA
# override (010-generate-ca.sh), the bootstrap script is extracted from the
# kubeadm-service-bootstrap Secret and executed on this node. The node is the
# one of the gate nodes (see values.yaml) whose IP is configured here, its
# bootstrap phase:
#   init          - the first node: kubeadm init
#   control-plane - the rest of control plane nodes: kubeadm join
#   worker        - kubeadm join
# Nodes join with the bootstrap token created after kubeadm init
# (032-create-join-token.sh), it is passed to the bootstrap script as
# KUBEADM_TOKEN.
# Usage: 030-kubeadm-bootstrap.sh [<phase>]
# If the phase is given, the script does nothing on nodes of other phases:
# this allows to run it on all nodes phase by phase.

set -ex

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${KUBEADM_CHART:="./charts/kubeadm"}"
: "${VALUES:="./tools/deployment/kubeadm/values.yaml"}"
: "${HELM:="helm"}"
PHASE="${1:-}"

nodes() {
  python3 - "${VALUES}" << 'EOF'
import sys

import yaml

with open(sys.argv[1]) as f:
    nodes = yaml.safe_load(f)['nodes']
for i, node in enumerate(nodes):
    phase = 'init' if i == 0 else node['role']
    print(node['name'], node['ip'], node['role'], phase)
EOF
}

read -r NODE_NAME NODE_IP _ NODE_PHASE < <(
  while read -r name ip role phase; do
    if ip -4 -o addr show | grep -q " inet ${ip}/"; then
      echo "${name} ${ip} ${role} ${phase}"
    fi
  done < <(nodes))
if [[ -z "${NODE_NAME}" ]]; then
  echo "None of the gate node IPs is configured on this node" >&2
  exit 1
fi
if [[ -n "${PHASE}" && "${PHASE}" != "${NODE_PHASE}" ]]; then
  echo "${NODE_NAME} is bootstrapped in the ${NODE_PHASE} phase, skipping"
  exit 0
fi

case "${NODE_PHASE}" in
  init)
    NODE_ROLE=master
    KUBEADM_ARGS=(init --config /etc/kubernetes/kubeadm/init_config.yaml)
    ;;
  control-plane)
    NODE_ROLE=master
    KUBEADM_ARGS=(join --config /etc/kubernetes/kubeadm/join_config.yaml)
    ;;
  worker)
    NODE_ROLE=worker
    KUBEADM_ARGS=(join --config /etc/kubernetes/kubeadm/join_worker_config.yaml)
    ;;
esac

print_diagnostics() {
  set +e
  sudo systemctl status kubelet --no-pager
  sudo journalctl -u kubelet --no-pager | tail -n 100
  sudo crictl ps -a
  for component in haproxy etcd kube-apiserver kube-controller-manager kube-scheduler; do
    for id in $(sudo crictl ps -a -q --name "${component}"); do
      echo "=== ${component} ${id}"
      sudo crictl logs --tail 50 "${id}"
    done
  done
}

# The bootstrap script contains the CA key: keep it private
SCRIPT_DIR=$(mktemp -d)
trap 'rm -rf "${SCRIPT_DIR}"' EXIT
chmod 0700 "${SCRIPT_DIR}"

${HELM} template kubeadm "${KUBEADM_CHART}" \
  -f "${VALUES}" \
  -f "${WORK_DIR}/ca-values.yaml" \
  --set manifests.secret_bootstrap=true \
  --set bootstrap.string_data=true \
  --show-only templates/entrypoint.yaml > "${SCRIPT_DIR}/kubeadm.yaml"

python3 - "${SCRIPT_DIR}/kubeadm.yaml" "${SCRIPT_DIR}/bootstrap.sh" << 'EOF'
import sys

import yaml

with open(sys.argv[1]) as f:
    for doc in yaml.safe_load_all(f):
        if doc and doc.get('kind') == 'Secret' and \
                doc['metadata']['name'] == 'kubeadm-service-bootstrap':
            with open(sys.argv[2], 'w') as out:
                out.write(doc['stringData']['script'])
            break
    else:
        sys.exit('Secret kubeadm-service-bootstrap is not found')
EOF

if [[ "${NODE_PHASE}" != "init" ]]; then
  # the token must not get to the logs
  { set +x; } 2> /dev/null
  KUBEADM_TOKEN=$(cat "${WORK_DIR}/join-token")
  export KUBEADM_TOKEN
  set -x
fi

if ! sudo --preserve-env=KUBEADM_TOKEN env NODE_NAME="${NODE_NAME}" NODE_IP="${NODE_IP}" NODE_ROLE="${NODE_ROLE}" \
    bash "${SCRIPT_DIR}/bootstrap.sh" -- "${KUBEADM_ARGS[@]}"; then
  print_diagnostics
  exit 1
fi

# kubeadm generated the PKI, the CA is the only part delivered by the chart
sudo openssl verify -CAfile /etc/kubernetes/pki/ca.crt /var/lib/kubelet/pki/kubelet-client-current.pem
if [[ "${NODE_ROLE}" == "master" ]]; then
  sudo openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt
  sudo openssl verify -CAfile /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd/server.crt
fi

# the node joined via the first control plane node, kubelet must use the VIP
CONTROL_PLANE_ENDPOINT=$(python3 -c \
  'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["kubeconfig"]["controlPlaneEndpoint"])' \
  "${VALUES}")
sudo grep -qx " *server: https://${CONTROL_PLANE_ENDPOINT}" /etc/kubernetes/kubelet.conf
sudo systemctl is-active kubelet
