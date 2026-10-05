{{/*
  this is an anonymous function which is responsible for generating
  bootstrapping script (can be called by cloudinit)
*/}}
{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $nodename := index . 2 -}}
{{- $fs := dict -}}

{{- $allNodes := get $k8sConfDict "allNodes" -}}
{{- range $k,$v := $allNodes -}}
{{- $_ := set $fs (print "allnodes/" $k) $v -}}
{{- end -}}
{{- $controlPlaneNodes := get $k8sConfDict "controlPlaneNodes" -}}
{{- range $k,$v := $controlPlaneNodes -}}
{{- $_ := set $fs (print "ctrlnodes/" $k) $v -}}
{{- end -}}

{{- if ne $nodename "" -}}
{{/* per node is mentioned only in fs-pki, and in this case we'll need to know */}}
{{- $perNode := get $k8sConfDict "perNode" -}}
{{- $node := get $perNode $nodename -}}
{{- range $k,$v := $node -}}
{{- $_ := set $fs (print "per-node/" $k) $v -}}
{{- end -}}
{{- end -}}

{{- $sharedLibsContent :=  get $k8sConfDict "sharedLibsContent" -}}
{{- $cmdHookContent := get $k8sConfDict "cmdHookContent" -}}

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

set -euo pipefail

# rootfs path (used to run mock tests. must be "" in real life)
ROOTFS="${ROOTFS:-}"
# directory where host fs is mounted if we run in the pod (shold be "" in this script)
HOST_DIR="${HOST_DIR:-}"

# for envsubst and heredoc, compatible with anchor, where all this is set on daemonsets
export NODE_ROLE="${NODE_ROLE:-master}"
export NODE_NAME="${NODE_NAME:-$(hostname -s)}"
export NODE_IP="${NODE_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"

echo Called with $# args: $@

# this value will be non empty if script was generated for specific name (e.g. if there are some files in per-node)
expected_node_name="{{ $nodename }}"
if [ -n "$expected_node_name" ]; then
  [ "$NODE_NAME" != "$expected_node_name" ] && echo "WARNING: Config for $expected_node_name is getting applied to $NODE_NAME"
fi
ensure_fs() {
  base64 -d << 'EOF_TAR_DATA' | tar -x -C "${ROOTFS}/tmp"
{{ $fs | include "tar" | b64enc }}
EOF_TAR_DATA
}
cleanup_fs() {
{{- range $path, $_ := $fs }}
  rm -rf $(dirname "${ROOTFS}/tmp/{{ $path }}") || true
{{- end }}
  echo "cleanup_fs is done"
}

{{/* adding shared bash functions */}}
{{ $sharedLibsContent }}
# end of common functions

cmd_hook () {
{{ $cmdHookContent }}
  return 1
}

kubeadm_args=("init")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) # everything after -- goes to `kubeadm`
      shift
      kubeadm_args=("$@")
      break
      ;;
    *)
      addons_shift=0
      if ! cmd_hook $@; then
        echo "Unknown option: $1" >&2
        exit 1
      fi
      shift $addons_shift
      ;;
  esac
done

ensure_fs

sync_certs
sync_kubelet || true
sync_kubeconfigs
sync_kubeadm

sync_vip

sync_cri
sync_kube_cgroup

k8s_up

systemctl daemon-reload
systemctl enable kubelet
systemctl restart kubelet

kubeadm ${kubeadm_args[@]+"${kubeadm_args[@]}"}

cleanup_fs

