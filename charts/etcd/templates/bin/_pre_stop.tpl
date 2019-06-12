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

function cleanup_host {
    rm -f $MANIFEST_PATH
    rm -rf /etcd-etc/tls/
    {{- if .Values.etcd.cleanup_data }}
    rm -rf /etcd-data/*
    {{- end }}
}

# Let the anchor process know it should not try to start the server.
touch /tmp/stopping

{{- if .Values.anchor.enable_cleanup }}
while true; do
    if etcdctl member list > /tmp/stop_members; then
        if grep $PEER_ENDPOINT /tmp/stop_members; then
            # Find and remove the member from the cluster.
            MEMBER_ID=$(grep $PEER_ENDPOINT /tmp/stop_members | awk -F ', ' '{ print $1 }')
            etcdctl member remove $MEMBER_ID
        else
            cleanup_host
            touch /tmp/stopped
            exit 0
        fi
    else
        echo Failed to locate existing cluster
    fi

    sleep {{ .Values.anchor.period }}
done
{{- end }}
touch /tmp/stopped
