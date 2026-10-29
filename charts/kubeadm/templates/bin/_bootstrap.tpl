{{/*
  the bootstrap script: makes a node a node of the cluster with the files of
  the values, kubeadm init (or kubeadm join, the arguments after --). It is
  delivered with the bootstrap Secrets (bootstrap.action: bootstrap) and run on
  the node (it can be called by cloud-init), phase by phase (see
  templates/phases/snippets/common/_phases.sh.tpl):
    ca-guard          - refuses to go on if the values deliver other CA keys
                        than the ones of the node
    certs             - the certificates
    kubeconfigs       - the kubeconfigs
    kubelet           - the certificates and the kubeconfig of kubelet, its
                        unit and configuration
    kubeadm-config    - the configurations of kubeadm
    vip               - the VIP of the control plane endpoint
    cri               - the container runtime, restarted if it is changed
    kube-cgroup       - the kube-cgroup service
    binaries          - kubeadm, kubectl, kubelet
    k8s-up            - swap, the kernel modules and sysctl
    kubelet-start     - kubelet is (re)started
    kubeadm           - kubeadm init (or the arguments after --), then the
                        configuration of kubelet of the chart again
    annotate          - the node with the configurations it runs with: the
                        first pass of the reconcile doesn't apply them again
    checks            - checks.bootstrap
*/}}
{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $nodename := index . 2 -}}
{{- $fs := dict -}}

{{/* all the archives of the node in one, unpacked to /run/kubeadm/<archive> */}}
{{- range $archive := list "all" "ctrl" -}}
{{- range $k,$v := get $k8sConfDict.fs $archive -}}
{{- $_ := set $fs (print $archive "/" $k) $v -}}
{{- end -}}
{{- end -}}
{{- if ne $nodename "" -}}
{{- range $archive := list "all-pernode" "ctrl-pernode" -}}
{{- range $k,$v := get (get $k8sConfDict.fs $archive) $nodename -}}
{{- $_ := set $fs (print $archive "/" $k) $v -}}
{{- end -}}
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

# for heredoc and subst_node_env, compatible with reconcile, where all this is set on daemonsets
export NODE_ROLE="${NODE_ROLE:-master}"
export NODE_NAME="${NODE_NAME:-$(hostname -s)}"
export NODE_IP="${NODE_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"

echo Called with $# args: $@

# this value will be non empty if script was generated for specific name (e.g. if there are some files in per-node)
expected_node_name="{{ $nodename }}"
if [ -n "$expected_node_name" ]; then
  [ "$NODE_NAME" != "$expected_node_name" ] && echo "WARNING: Config for $expected_node_name is getting applied to $NODE_NAME"
fi
# the files delivered by the chart, the reconcile script finds them there too
ensure_fs() {
  local teepath="" # for debug
  [ -n "${ROOTFS}" ] && teepath="${ROOTFS}/tmp/fs.{{ $envAll.Values.bootstrap.compress_fs }}"
  mkdir -p -m 0700 "${ROOTFS}/run/kubeadm"
{{ $archive := $fs | include "tar" -}}
{{- if eq $envAll.Values.bootstrap.compress_fs "tar" -}}
  base64 -d << 'EOF_ARCHIVE_DATA' | tee $teepath | tar -x -C "${ROOTFS}/run/kubeadm"
{{ else if eq $envAll.Values.bootstrap.compress_fs "tgz" -}}
  {{- $archive = (dict "content" $archive "calc_crc32" true ) | include "gzip" -}}
  base64 -d << 'EOF_ARCHIVE_DATA' | tee $teepath | tar -xz -C "${ROOTFS}/run/kubeadm"
{{ else -}}{{- fail (printf "Unsupported format %s" $envAll.Values.bootstrap.compress_fs ) -}}{{ end -}}
{{- $archive | b64enc }}
EOF_ARCHIVE_DATA
}
cleanup_fs() {
{{- $dirs := dict -}}
{{- range $path, $_ := $fs -}}
{{- $_ := set $dirs (index (splitList "/" $path) 0) true -}}
{{- end -}}
{{- range $dir, $_ := $dirs }}
  rm -rf "${ROOTFS}/run/kubeadm/{{ $dir }}" || true
{{- end }}
  echo "cleanup_fs is done"
}

# the node as the client of the API (kubelet.conf after kubeadm): the shared
# functions use kubectl
kubectl() {
  command kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/kubelet.conf" "$@"
}

# the first pass of the reconcile doesn't apply the configurations again
phase_annotate() {
  annotate_applied_configs
}


{{/* adding shared bash functions */}}
{{ $sharedLibsContent }}
{{- if $envAll.Values.checks.bootstrap }}
{{ get $k8sConfDict.sharedLibs "checks" }}
{{- end }}
{{ tuple $envAll "templates/phases/snippets/common/_phases.sh.tpl" | include "kubeadm.bundle.template" }}
# end of common functions

cmd_hook () {
{{ $cmdHookContent }}
  return 1
}

phase_ca_guard() {
  guard_ca
}

phase_certs() {
  sync_certs
}

phase_kubeconfigs() {
  sync_kubeconfigs
}

phase_kubelet() {
  sync_kubelet || true
}

phase_kubeadm_config() {
  sync_kubeadm
}

phase_vip() {
  sync_vip
}

phase_cri() {
  local cri_changed=false
  sync_cri_install && cri_changed=true
  sync_cri && cri_changed=true
  if [[ $cri_changed == true ]]; then
    restart_cri
  fi
}

phase_kube_cgroup() {
  sync_kube_cgroup
}

phase_binaries() {
  sync_binaries kubeadm kubectl kubelet || true
}

phase_k8s_up() {
  k8s_up
}

phase_kubelet_start() {
  systemctl daemon-reload
  systemctl enable kubelet
  systemctl restart kubelet
}

# the configuration of kubeadm (--config) with the bootstrap token of the join
# (KUBEADM_TOKEN) to the file $2: the files of the node don't have it
kubeadm_token_config() {
  sed "s|\${KUBEADM_TOKEN}|${KUBEADM_TOKEN:-}|g" "${ROOTFS}$1" > "$2"
}

phase_kubeadm() {
  local args=() arg dir config=false rc=0
  dir=$(mktemp -d)
  for arg in ${kubeadm_args[@]+"${kubeadm_args[@]}"}; do
    if [ "${config}" = true ]; then
      kubeadm_token_config "${arg}" "${dir}/config.yaml"
      arg="${dir}/config.yaml"
      config=false
    elif [ "${arg}" = "--config" ]; then
      config=true
    elif [[ "${arg}" == --config=* ]]; then
      kubeadm_token_config "${arg#--config=}" "${dir}/config.yaml"
      arg="--config=${dir}/config.yaml"
    fi
    args+=("${arg}")
  done
  kubeadm ${args[@]+"${args[@]}"} || rc=$?
  rm -rf "${dir}"
  [ "${rc}" -eq 0 ] || return "${rc}"

  # kubeadm writes its kubelet configuration (/var/lib/kubelet/config.yaml):
  # the one of the chart again, as the reconcile does, and the kubeconfig of
  # the control plane endpoint
  if sync_kubelet; then
    systemctl daemon-reload
    systemctl restart kubelet
  fi
}

phase_checks() {
  run_checks check_api
}

PHASES=(
  ca-guard certs kubeconfigs kubelet kubeadm-config vip cri kube-cgroup binaries
  k8s-up kubelet-start kubeadm annotate
{{- if $envAll.Values.checks.bootstrap }}
  checks
{{- end }}
)

kubeadm_args=("init")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) # everything after -- goes to `kubeadm`
      shift
      kubeadm_args=("$@")
      break
      ;;
    *)
      if phases_arg "$@"; then
        shift $phases_shift
        continue
      fi
      addons_shift=0
      if ! cmd_hook $@; then
        echo "Unknown option: $1" >&2
        exit 1
      fi
      shift $addons_shift
      ;;
  esac
done
phases_check "${PHASES[@]}"

ensure_fs
run_phases "${PHASES[@]}"
cleanup_fs
