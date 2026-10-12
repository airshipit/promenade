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

# Generate the kustomize catalog of the cluster: Calico and the kubeadm chart
# itself (day 2: the anchor daemonsets keep the nodes in sync with the chart
# values). The chart is rendered with the same values it was bootstrapped
# with, so there is no configuration drift between day 0 and day 2.
#
# The catalog is plain manifests: it is applied with `kubectl apply -k`
# (040-deploy-catalog.sh) and can be used as is as a source of Flux or
# Argo CD. It contains the CA key, it's kept private and never published.
#
# Extra helm arguments (e.g. -f) can be passed to the script, they are used
# to change the cluster on day 2 (see 060-day2-reconfigure.sh,
# 070-day2-upgrade.sh).

set -ex

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${CATALOG:="${WORK_DIR}/catalog"}"
: "${KUBEADM_CHART:="./charts/kubeadm"}"
: "${VALUES:="./tools/deployment/kubeadm/values.yaml"}"
: "${HELM:="helm"}"
: "${NAMESPACE:="kube-system"}"
: "${CALICO_VERSION:="v3.32.1"}"
: "${CALICO_MANIFEST_URL:="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"}"
# pod network MTU below the one of the vxlan overlay network of the gate
: "${CALICO_VETH_MTU:="1400"}"

POD_CIDR=$(python3 -c \
  'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["network"]["pod_cidr"])' \
  "${VALUES}")

install -d -m 0700 "${CATALOG}/calico" "${CATALOG}/kubeadm"

curl -fsSL --retry 5 -o "${CATALOG}/calico/calico.yaml" "${CALICO_MANIFEST_URL}"
cat > "${CATALOG}/calico/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - calico.yaml
images:
  - name: docker.io/calico/cni
    newName: quay.io/calico/cni
  - name: docker.io/calico/node
    newName: quay.io/calico/node
  - name: docker.io/calico/kube-controllers
    newName: quay.io/calico/kube-controllers
configMapGenerator:
  - name: calico-config
    namespace: kube-system
    behavior: merge
    literals:
      - veth_mtu=${CALICO_VETH_MTU}
patches:
  # strategic merge: env entries are merged by name, the existing ones (e.g.
  # CALICO_IPV4POOL_IPIP) are replaced
  - target:
      kind: DaemonSet
      name: calico-node
    patch: |
      apiVersion: apps/v1
      kind: DaemonSet
      metadata:
        name: calico-node
        namespace: kube-system
      spec:
        template:
          spec:
            containers:
              - name: calico-node
                env:
                  - name: CALICO_IPV4POOL_CIDR
                    value: "${POD_CIDR}"
                  # nodes are connected by the overlay network: plain routing
                  - name: CALICO_IPV4POOL_IPIP
                    value: Never
                  - name: IP_AUTODETECTION_METHOD
                    value: kubernetes-internal-ip
generatorOptions:
  disableNameSuffixHash: true
EOF

( umask 077
  ${HELM} template kubeadm "${KUBEADM_CHART}" \
    --namespace "${NAMESPACE}" \
    -f "${VALUES}" \
    -f "${WORK_DIR}/ca-values.yaml" \
    "$@" > "${CATALOG}/kubeadm/kubeadm.yaml" )
cat > "${CATALOG}/kubeadm/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - kubeadm.yaml
EOF

cat > "${CATALOG}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - calico
  - kubeadm
EOF

kubectl kustomize "${CATALOG}" > /dev/null
find "${CATALOG}" -type f | sort
