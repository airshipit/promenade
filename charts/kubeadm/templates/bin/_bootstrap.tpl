{{/*
  the script of the bootstrap Secrets: run on the node phase by phase
  (templates/phases/_phase_runner.tpl), the phases of the profile
  bootstrap.profile (bootstrap.profiles in the values)
*/}}
{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $nodename := index . 2 -}}
{{- $profile := $envAll.Values.bootstrap.profile -}}
{{- if not (hasKey $envAll.Values.bootstrap.profiles $profile) -}}
{{- fail (printf "bootstrap.profile %s isn't one of bootstrap.profiles" $profile) -}}
{{- end -}}
{{- $fs := dict -}}

{{/* all the archives of the node in one, unpacked to /run/kubeadm/<archive> */}}
{{- range $archive := list "all" "ctrl" -}}
{{- range $k,$v := get (get $k8sConfDict "fs") $archive -}}
{{- $_ := set $fs (print $archive "/" $k) $v -}}
{{- end -}}
{{- end -}}
{{- if ne $nodename "" -}}
{{- range $archive := list "all-pernode" "ctrl-pernode" -}}
{{- range $k,$v := get (get (get $k8sConfDict "fs") $archive) $nodename -}}
{{- $_ := set $fs (print $archive "/" $k) $v -}}
{{- end -}}
{{- end -}}
{{- end -}}


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

{{/* the runner (run_phases) and the functions of the phases of the profile
     ("+<phase>" too) linked (templates/lib/_linker.tpl), then the phases: a
     phase is a function */}}
{{- $phases := index $envAll.Values.bootstrap.profiles $profile -}}
{{- $needs := list "run_phases" -}}
{{- range $phase := $phases -}}
  {{- $needs = append $needs (trimPrefix "+" $phase) -}}
{{- end }}
{{ include "linker" (dict "symbols" (get $k8sConfDict "symbols") "needs" $needs) }}
PHASES=(
{{- range $phase := $phases }}
  {{ $phase | squote }}
{{- end }}
)
# end of common functions

ensure_fs
run_phases "$@"
cleanup_fs
