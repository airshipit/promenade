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

compare_copy_files() {

    {{range .Values.anchor.files_to_copy}}
    if [ ! -e /host{{ .dest }} ] || ! cmp -s {{ .source }} /host{{ .dest }}; then
        mkdir -p $(dirname /host{{ .dest }})
        cp {{ .source }} /host{{ .dest }}
    fi
    {{end}}
}

cleanup() {

    {{range .Values.anchor.files_to_copy}}
    rm -f /host{{ .dest }}
    {{end}}
}

while true; do

    if [ -e /tmp/stop ]; then
        echo Stopping
        cleanup
        break
    fi

    # Compare and replace files on Genesis host if needed
    # Copy files to other master nodes
    compare_copy_files

    sleep {{ .Values.anchor.period }}
done
