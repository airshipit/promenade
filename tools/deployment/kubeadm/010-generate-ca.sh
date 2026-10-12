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
# They are written as a values override of the kubeadm chart, kubeadm
# generates the rest of the PKI (all certificates and kubeconfigs) on every
# node, so control plane nodes join without kubeadm uploading certificates.
#
# Join credentials (a bootstrap token) aren't part of the values: they are
# short-lived and created once the cluster exists (032-create-join-token.sh).

set -ex

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${CA_DAYS:="3650"}"

OVERRIDE="${WORK_DIR}/ca-values.yaml"

install -d -m 0700 "${WORK_DIR}"
CA_DIR=$(mktemp -d)
trap 'rm -rf "${CA_DIR}"' EXIT

gen_ca() {
  local name="$1" cn="$2"
  openssl genrsa -out "${CA_DIR}/${name}.key" 2048
  openssl req -x509 -new -nodes -sha256 \
    -key "${CA_DIR}/${name}.key" \
    -subj "/CN=${cn}" \
    -days "${CA_DAYS}" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" \
    -out "${CA_DIR}/${name}.crt"
  openssl x509 -in "${CA_DIR}/${name}.crt" -noout -subject -enddate
}

gen_ca ca kubernetes
gen_ca etcd_ca etcd-ca
gen_ca front_proxy_ca front-proxy-ca
openssl genrsa -out "${CA_DIR}/sa.key" 2048
openssl rsa -in "${CA_DIR}/sa.key" -pubout -out "${CA_DIR}/sa.pub"

pem() {
  sed 's/^/      /' "${CA_DIR}/$1"
}

(
  umask 077
  cat > "${OVERRIDE}" << EOF
certs:
  ca:
    crt: |
$(pem ca.crt)
    key: |
$(pem ca.key)
  etcd_ca:
    crt: |
$(pem etcd_ca.crt)
    key: |
$(pem etcd_ca.key)
  front_proxy_ca:
    crt: |
$(pem front_proxy_ca.crt)
    key: |
$(pem front_proxy_ca.key)
  sa:
    key: |
$(pem sa.key)
    pub: |
$(pem sa.pub)
EOF
)
