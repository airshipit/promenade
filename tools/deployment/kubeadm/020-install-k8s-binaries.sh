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

# The bootstrap script of the kubeadm chart expects kubeadm, kubelet and
# kubectl to be present on the node (kubelet.service runs
# /usr/local/bin/kubelet). Install the version of the gate values.

set -ex

: "${VALUES:="./tools/deployment/kubeadm/values.yaml"}"
: "${K8S_DOWNLOAD_URL:="https://dl.k8s.io/release"}"
: "${CNI_PLUGINS_VERSION:="v1.7.1"}"
: "${CNI_PLUGINS_URL:="https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"}"

KUBERNETES_VERSION=$(python3 -c \
  'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["cluster_config"]["kubernetesVersion"])' \
  "${VALUES}")

for bin in kubeadm kubelet kubectl; do
  sudo curl -fsSL --retry 5 -o "/usr/local/bin/${bin}" \
    "${K8S_DOWNLOAD_URL}/${KUBERNETES_VERSION}/bin/linux/amd64/${bin}"
  sudo chmod 0755 "/usr/local/bin/${bin}"
done

sudo mkdir -p /opt/cni/bin
curl -fsSL --retry 5 "${CNI_PLUGINS_URL}" | sudo tar -xz -C /opt/cni/bin

# envsubst is used by the bootstrap script
sudo apt-get install -y gettext-base

kubeadm version -o short
kubelet --version
kubectl version --client
