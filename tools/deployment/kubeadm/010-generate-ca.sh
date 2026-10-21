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

# Generate the only secrets the user has to provide: the CAs of the cluster
# (Kubernetes, etcd and front proxy) and the service account signing key.
# They are written as a values override of the kubeadm chart by its gen-pki.sh
# tool (manifests.secret_tools), kubeadm generates the rest of the PKI (all
# certificates and kubeconfigs) on every node, so control plane nodes join
# without kubeadm uploading certificates.
#
# Join credentials (a bootstrap token) aren't part of the values: they are
# short-lived and created once the cluster exists (032-create-join-token.sh).

set -exo pipefail

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${KUBEADM_CHART:="./charts/kubeadm"}"
: "${HELM:="helm"}"
# used by gen-pki.sh
export CA_DAYS="${CA_DAYS:-3650}"

install -d -m 0700 "${WORK_DIR}"

# the defaults of the chart: the gate values need the certs to render
${HELM} template kubeadm "${KUBEADM_CHART}" \
  --set manifests.secret_tools=true \
  | sed -n 's/^ *gen-pki.sh: *\(.*\)/\1/p' | base64 -d \
  | bash -s -- --out-file "${WORK_DIR}/ca-values.yaml"
# an empty script (e.g. the tool isn't rendered) generates nothing
test -s "${WORK_DIR}/ca-values.yaml"