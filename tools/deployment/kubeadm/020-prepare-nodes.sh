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

# The bootstrap script of the kubeadm chart installs kubeadm, kubelet and
# kubectl itself (binaries.* of the chart values) and the container runtime
# (install_cri of the gate values), the nodes need the CNI plugins

set -ex

: "${CNI_PLUGINS_VERSION:="v1.7.1"}"
: "${CNI_PLUGINS_URL:="https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"}"

sudo mkdir -p /opt/cni/bin
curl -fsSL --retry 5 "${CNI_PLUGINS_URL}" | sudo tar -xz -C /opt/cni/bin
