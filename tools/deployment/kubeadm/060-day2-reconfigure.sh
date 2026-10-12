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

# Day 2 reconfiguration: change the cluster configuration in the chart
# values, regenerate and apply the catalog, and check that the anchor applies
# it to the control plane (kubeadm upgrade node).

set -ex

: "${DAY2_DIR:="./tools/deployment/kubeadm/day2"}"

NODE_PORT_RANGE=$(python3 -c \
  'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["network"]["service_node_port_range"])' \
  "${DAY2_DIR}/reconfigure.yaml")

./tools/deployment/kubeadm/035-generate-catalog.sh -f "${DAY2_DIR}/reconfigure.yaml"
./tools/deployment/kubeadm/040-deploy-catalog.sh

for name in $(kubectl get nodes -l kubernetes-apiserver=enabled -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n kube-system wait --for=condition=Ready pod --timeout=300s \
    -l component=kube-apiserver --field-selector "spec.nodeName=${name}"
  kubectl -n kube-system get pod "kube-apiserver-${name}" \
    -o jsonpath='{range .spec.containers[0].command[*]}{@}{"\n"}{end}' | \
    grep -Fx -- "--service-node-port-range=${NODE_PORT_RANGE}"
done
kubectl get --raw /livez
