#!/bin/sh
# Copyright 2026 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prepares the files of the reconcile script, which runs on the host with
# chroot (see the daemonsets), like the bootstrap script prepares its ones.
# The mounts are made in the pod only (the host root is mounted with
# HostToContainer propagation), the host doesn't see them:
# - /run/kubeadm: the files delivered by the chart, where the bootstrap script
#   unpacks them
# - anchor.reconcile.host_dir: the files of the reconcile script itself (script,
#   service account, state)

set -eu

HOST=/host
RECONCILE_DIR={{ .Values.anchor.reconcile.host_dir | quote }}
SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount

case "${RECONCILE_DIR}" in
  /?*) ;;
  *) echo "anchor.reconcile.host_dir must be an absolute path: '${RECONCILE_DIR}'" >&2; exit 1 ;;
esac

private_dir() {
  mkdir -p "$1"
  mount -t tmpfs -o mode=0700 tmpfs "$1"
}

bind() {
  mkdir -p "$2"
  mount -o bind "$1" "$2"
}

private_dir "${HOST}/run/kubeadm"
# the archives mounted to the pod (the daemonset of the workers has no ctrl ones)
for archive in all ctrl all-pernode ctrl-pernode; do
  if [ -s "/tmp/fs/${archive}.tar" ]; then
    mkdir -p "${HOST}/run/kubeadm/${archive}"
    tar -xf "/tmp/fs/${archive}.tar" -C "${HOST}/run/kubeadm/${archive}"
  fi
done

private_dir "${HOST}${RECONCILE_DIR}"
bind /tmp/bin "${HOST}${RECONCILE_DIR}/bin"
# the token is rotated by kubelet
bind "${SA_DIR}" "${HOST}${RECONCILE_DIR}/sa"
cat > "${HOST}${RECONCILE_DIR}/kubeconfig" << EOF
apiVersion: v1
kind: Config
clusters:
  - name: kubernetes
    cluster:
      server: https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}
      certificate-authority: ${RECONCILE_DIR}/sa/ca.crt
users:
  - name: reconcile
    user:
      tokenFile: ${RECONCILE_DIR}/sa/token
contexts:
  - name: reconcile
    context:
      cluster: kubernetes
      user: reconcile
      namespace: $(cat "${SA_DIR}/namespace")
current-context: reconcile
EOF
