{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

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

# The entrypoint of the anchor container. It prepares the files of the
# reconcile in mounts only the pod sees, then runs the reconcile on the host
# with chroot:
# 1. /run/kubeadm gets the files of the chart, the phase runner puts them in
#    the same place on the host,
# 2. anchor.reconcile.host_dir gets the reconcile script, the service account
#    and its state.
# The host root is mounted with HostToContainer propagation, so the host
# doesn't see these mounts.

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
  # the archives mounted to the pod, the workers don't get the ctrl ones
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
# the files of the reconcile: this script, the service account and the state
RECONCILE_DIR={{ $envAll.Values.anchor.reconcile.host_dir | quote }}

# namespace of the anchor pod: its service account runs the kubelet restart job
NAMESPACE="$(cat "${RECONCILE_DIR}/sa/namespace")"

export KUBECONFIG="${RECONCILE_DIR}/kubeconfig"

# kubeadm runs without the KUBECONFIG of kubectl, verbose except for version
kubeadm() {
  if [[ "$1" == "version" ]]; then
    env -u KUBECONFIG kubeadm "$@"
  else
    env -u KUBECONFIG kubeadm --v=5 "$@"
  fi
}

{{/* the reconcile function and the functions it needs */}}
{{ include "linker" (dict "symbols" (get $mainDict "symbols") "needs" (list "reconcile")) }}
# end of common functions

reconcile
EOF_RECONCILE
}

ensure_fs
# the reconcile runs kubeadm, kubectl and kubelet by name. chroot keeps the
# environment of the container, so the PATH is taken from the login shell of
# the host
host_path_var=$(chroot "${HOST}" /bin/bash -lc 'printf "\n%s" "$PATH"' </dev/null 2>/dev/null | tail -n1) || true
[ -z "${host_path_var}" ] || export PATH="${host_path_var}:${PATH}"
exec chroot "${HOST}" /bin/bash "${RECONCILE_DIR}/reconcile"
