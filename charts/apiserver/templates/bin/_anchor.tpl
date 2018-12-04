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

set -x

snapshot_files() {
    SNAPSHOT_DIR=${1}
    {{ range $dest, $source := .Values.const.files_to_copy }}
    mkdir -p $(dirname "${SNAPSHOT_DIR}{{ $dest }}")
    cp "{{ $source }}" "${SNAPSHOT_DIR}{{ $dest }}"
    {{- end }}
    {{ range $key, $val := .Values.conf }}
    cp "/tmp/etc/{{ $val.file }}" "${SNAPSHOT_DIR}/etc/kubernetes/apiserver/{{ $val.file }}"
    {{- end }}
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
    SRC="${SNAPSHOT_DIR}/etc/kubernetes/apiserver/{{ $val.file }}"
    DEST="/host/etc/kubernetes/apiserver/{{ $val.file }}"
    if [ ! -e "${DEST}" ] || ! cmp -s "${SRC}" "${DEST}"; then
        mkdir -p $(dirname "${DEST}")
        cp "${SRC}" "${DEST}"
        chmod go-rwx "${DEST}"
    fi
    {{- end }}
}

cleanup() {
    {{- range $dest, $source := .Values.const.files_to_copy }}
    rm -f "/host{{ $dest }}"
    {{- end }}
    {{  range $key, $val := .Values.conf }}
    rm -f "/host/{{ $val.file }}"
    {{- end }}
}


SNAPSHOT_DIR=$(mktemp -d)

snapshot_files "${SNAPSHOT_DIR}"

while true; do
    if [ -e /tmp/stop ]; then
        echo Stopping
        cleanup
        break
    fi

    # Compare and replace files on Genesis host if needed
    # Copy files to other master nodes
    compare_copy_files "${SNAPSHOT_DIR}"

    sleep {{ .Values.anchor.period }}
done
