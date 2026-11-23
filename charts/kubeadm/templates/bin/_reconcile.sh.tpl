{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

#!/bin/sh
# Copyright 2025 AT&T Intellectual Property.  All other rights reserved.
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

# The reconcile of the anchor. It starts in the anchor container (busybox):
# ensure_fs prepares the files of the reconcile, the script below runs on the
# host with chroot, like the bootstrap script prepares its files. The mounts
# are made in the pod only (the host root is mounted with HostToContainer
# propagation), the host doesn't see them:
# - /run/kubeadm: the files delivered by the chart, where the bootstrap script
#   unpacks them
# - anchor.reconcile.host_dir: the files of the reconcile itself (the script,
#   service account, state)

set -eu

HOST=/host
RECONCILE_DIR={{ $envAll.Values.anchor.reconcile.host_dir | quote }}
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

ensure_fs() {
  private_dir "${HOST}/run/kubeadm"
  # the archives mounted to the pod (the daemonset of the workers has no ctrl
  # ones)
  for archive in all ctrl all-pernode ctrl-pernode; do
    if [ -s "/tmp/fs/${archive}.tar" ]; then
      mkdir -p "${HOST}/run/kubeadm/${archive}"
      tar -xf "/tmp/fs/${archive}.tar" -C "${HOST}/run/kubeadm/${archive}"
    fi
  done

  private_dir "${HOST}${RECONCILE_DIR}"
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
  cat > "${HOST}${RECONCILE_DIR}/reconcile" << 'EOF_RECONCILE'
#!/bin/bash
set -xeuo pipefail

# rootfs path (used to run mock tests. must be "" in real life)
ROOTFS="${ROOTFS:-}"
# files of the reconcile only: this script, service account, state (see
# ensure_fs, the files delivered by the chart are in /run/kubeadm)
RECONCILE_DIR={{ $envAll.Values.anchor.reconcile.host_dir | quote }}

# namespace of the anchor pod: its service account runs the kubelet restart job
NAMESPACE="$(cat "${RECONCILE_DIR}/sa/namespace")"

export KUBECONFIG="${RECONCILE_DIR}/kubeconfig"

# kubeadm doesn't get the KUBECONFIG of kubectl
kubeadm() {
  if [[ "$1" == "version" ]]; then
    env -u KUBECONFIG kubeadm "$@"
  else
    env -u KUBECONFIG kubeadm --v=5 "$@"
  fi
}

{{/* the linked functions: the pass, the step of the main loop and their
     needs (templates/phases/modules/reconcile) */}}
{{ include "linker" (dict "symbols" (get $k8sConfDict "symbols") "needs" (list "reconcile")) }}
# end of common functions

reconcile
EOF_RECONCILE
}

ensure_fs
# the reconcile finds kubeadm, kubectl and kubelet (binaries.install_dir) by the
# PATH of the login shell of the host; chroot keeps the environment of the
# container, so it is taken from the host
host_path_var=$(chroot "${HOST}" /bin/bash -lc 'printf "\n%s" "$PATH"' </dev/null 2>/dev/null | tail -n1) || true
[ -z "${host_path_var}" ] || export PATH="${host_path_var}:${PATH}"
exec chroot "${HOST}" /bin/bash "${RECONCILE_DIR}/reconcile"
