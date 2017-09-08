#!/bin/sh

set -x

export PEER_ENDPOINT=https://$POD_IP:{{ .Values.service.peer.target_port }}
export MANIFEST_PATH=/manifests/{{ .Values.service.name }}.yaml

function cleanup_host {
    rm -f $MANIFEST_PATH
    rm -rf /etcd-etc/tls/
    {{- if .Values.etcd.cleanup_data }}
    rm -rf /etcd-data/*
    {{- end }}
}

# Let the anchor process know it should not try to start the server.
touch /tmp/stopping

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
