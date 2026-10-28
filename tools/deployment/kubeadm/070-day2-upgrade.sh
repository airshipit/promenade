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

# Day 2 upgrade to the next Kubernetes minor version: change the version in
# the chart values, regenerate and apply the catalog, and
# check that the anchor upgrades the control plane (kubeadm upgrade node),
# the addons and the kubelets.

set -ex

: "${DAY2_DIR:="./tools/deployment/kubeadm/day2"}"
: "${UPGRADE_TIMEOUT:="2400"}"

VERSION=$(python3 -c \
  'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["cluster_config"]["kubernetesVersion"])' \
  "${DAY2_DIR}/upgrade.yaml")

# day 2 changes accumulate as in a site catalog
./tools/deployment/kubeadm/035-generate-catalog.sh \
  -f "${DAY2_DIR}/reconfigure.yaml" \
  -f "${DAY2_DIR}/upgrade.yaml"
./tools/deployment/kubeadm/040-deploy-catalog.sh

image_tags() {
  kubectl -n kube-system get pods -l "$1" \
    -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | sed 's/.*://' | sort -u
}

upgraded() {
  [[ "$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u)" \
    == "${VERSION}" ]] || return 1
  local component
  for component in kube-apiserver kube-controller-manager kube-scheduler kube-proxy; do
    [[ "$(image_tags "component=${component}")" == "${VERSION}" ]] || \
      [[ "$(image_tags "k8s-app=${component}")" == "${VERSION}" ]] || return 1
  done
}

END=$(($(date +%s) + UPGRADE_TIMEOUT))
until upgraded; do
  if [[ "$(date +%s)" -gt "${END}" ]]; then
    echo "Timed out waiting for the upgrade to ${VERSION}" >&2
    kubectl -n kube-system logs -l release_group=kubeadm,application=kubernetes,component!=kubernetes-kubeadm-test \
      --tail=200 --prefix --max-log-requests=10 || true
    exit 1
  fi
  kubectl get nodes -o wide || true
  kubectl -n kube-system get pods -o wide || true
  sleep 30
done

kubectl version
kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=300s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s
kubectl -n kube-system get deployment coredns -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get --raw /livez
