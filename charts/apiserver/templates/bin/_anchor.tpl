#!/bin/sh
# Copyright 2017 AT&T Intellectual Property.  All other rights reserved.
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

set -xu

snapshot_files() {
    SNAPSHOT_DIR=${1}
    {{ range $dest, $source := .Values.const.files_to_copy }}
    mkdir -p $(dirname "${SNAPSHOT_DIR}{{ $dest }}")
    cp "{{ $source }}" "${SNAPSHOT_DIR}{{ $dest }}"
    {{- end }}
    {{ range $key, $val := .Values.conf }}
    {{- if $val.file }}
    cp "/tmp/etc/{{ $val.file }}" "${SNAPSHOT_DIR}/etc/kubernetes/apiserver/{{ $val.file }}"
    {{- end }}
    {{- end }}
    sed -i -e 's#_ADVERTISE_ADDRESS_#'$POD_IP'#g' "${SNAPSHOT_DIR}{{ .Values.anchor.kubelet.manifest_path }}/kubernetes-apiserver.yaml"
    sed -i -e 's#_ADVERTISE_PORT_#'{{ .Values.network.kubernetes_apiserver.port }}'#g' "${SNAPSHOT_DIR}{{ .Values.anchor.kubelet.manifest_path }}/kubernetes-apiserver.yaml"
    # annotate the static manifest with the name of the creating anchor pod
    sed -i "/created-by: /s/ANCHOR_POD/${POD_NAME}/" "${SNAPSHOT_DIR}{{ .Values.anchor.kubelet.manifest_path }}/kubernetes-apiserver.yaml"
}

compare_copy_files() {
    SNAPSHOT_DIR=${1}
    {{ range $dest, $source := .Values.const.files_to_copy }}
    SRC="${SNAPSHOT_DIR}{{ $dest }}"
    DEST="/host{{ $dest }}"
    if [ ! -e "${DEST}" ] || ! cmp -s "${SRC}" "${DEST}"; then
        mkdir -p $(dirname "${DEST}")
        cp "${SRC}" "${DEST}"
        chmod go-rwx "${DEST}"
    fi
    {{- end}}
    {{ range $key, $val := .Values.conf }}
    {{- if $val.file }}
    SRC="${SNAPSHOT_DIR}/etc/kubernetes/apiserver/{{ $val.file }}"
    DEST="/host/etc/kubernetes/apiserver/{{ $val.file }}"
    if [ ! -e "${DEST}" ] || ! cmp -s "${SRC}" "${DEST}"; then
        mkdir -p $(dirname "${DEST}")
        cp "${SRC}" "${DEST}"
        chmod go-rwx "${DEST}"
    fi
    {{- end }}
    {{- end }}
}

cleanup() {
    {{- range $dest, $source := .Values.const.files_to_copy }}
    rm -f "/host{{ $dest }}"
    {{- end }}
    {{  range $key, $val := .Values.conf }}
    {{- if $val.file }}
    rm -f "/host/etc/kubernetes/apiserver/{{ $val.file }}"
    {{- end }}
    {{- end }}
}


SNAPSHOT_DIR=$(mktemp -d)

snapshot_files "${SNAPSHOT_DIR}"

while true; do
    if [ -e /tmp/stop ]; then
        echo Stopping
        {{- if .Values.anchor.enable_cleanup }}
        cleanup
        {{- end }}
        break
    fi

    # Compare and replace files on Genesis host if needed
    # Copy files to other master nodes
    compare_copy_files "${SNAPSHOT_DIR}"

    sleep {{ .Values.anchor.period }}
done
