{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

#!/bin/bash
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

set -xeuo pipefail

# rootfs path (used to run mock tests. must be "" in real life)
ROOTFS="${ROOTFS:-}"
# files of the reconcile script only: script, service account, state, see
# ensure_fs (the files delivered by the chart are in /run/kubeadm)
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
