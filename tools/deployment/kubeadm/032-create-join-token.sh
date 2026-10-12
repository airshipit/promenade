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

# Create a short-lived bootstrap token for the nodes joining the cluster
# after kubeadm init, as a node provisioner would do: it doesn't take
# anything from the nodes, it accesses the new cluster with a client
# certificate it issues with the provided Kubernetes CA.
# The token is written to ${WORK_DIR}/join-token.

set -ex

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${VALUES:="./tools/deployment/kubeadm/values.yaml"}"
: "${TOKEN_TTL:="2 hours"}"
: "${API_TIMEOUT:="300"}"

API_SERVER=$(python3 -c \
  'import sys, yaml; print("https://%s:6443" % yaml.safe_load(open(sys.argv[1]))["nodes"][0]["ip"])' \
  "${VALUES}")

PKI_DIR=$(mktemp -d)
trap 'rm -rf "${PKI_DIR}"' EXIT
chmod 0700 "${PKI_DIR}"

python3 - "${WORK_DIR}/ca-values.yaml" "${PKI_DIR}" << 'EOF'
import sys

import yaml

with open(sys.argv[1]) as f:
    ca = yaml.safe_load(f)['certs']['ca']
for ext in ('crt', 'key'):
    with open('%s/ca.%s' % (sys.argv[2], ext), 'w') as out:
        out.write(ca[ext])
EOF

openssl genrsa -out "${PKI_DIR}/client.key" 2048
openssl req -new -key "${PKI_DIR}/client.key" \
  -subj "/O=system:masters/CN=kubeadm-gate-provisioner" \
  -out "${PKI_DIR}/client.csr"
openssl x509 -req -sha256 -days 1 \
  -in "${PKI_DIR}/client.csr" \
  -CA "${PKI_DIR}/ca.crt" -CAkey "${PKI_DIR}/ca.key" \
  -set_serial "0x$(openssl rand -hex 16)" \
  -extfile <(printf 'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n') \
  -out "${PKI_DIR}/client.crt"

kubectl_api() {
  kubectl --server "${API_SERVER}" \
    --certificate-authority "${PKI_DIR}/ca.crt" \
    --client-certificate "${PKI_DIR}/client.crt" \
    --client-key "${PKI_DIR}/client.key" "$@"
}

END=$(($(date +%s) + API_TIMEOUT))
until kubectl_api get --raw /readyz; do
  [[ "$(date +%s)" -lt "${END}" ]] || exit 1
  sleep 10
done

# The token must not get to the logs
{ set +x; } 2> /dev/null
TOKEN_ID=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
kubectl_api apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${TOKEN_ID}
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  token-id: "${TOKEN_ID}"
  token-secret: "${TOKEN_SECRET}"
  expiration: "$(date -u -d "+${TOKEN_TTL}" +%Y-%m-%dT%H:%M:%SZ)"
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: system:bootstrappers:kubeadm:default-node-token
EOF
( umask 077; echo "${TOKEN_ID}.${TOKEN_SECRET}" > "${WORK_DIR}/join-token" )
set -x
