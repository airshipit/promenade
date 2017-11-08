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

function copy_certificates {
    ETCD_NAME=$1

    set -e

    mkdir -p /etcd-etc/tls
    # Copy CA Certificates in place
    cp \
        /etc/etcd/tls/certs/client-ca.pem \
        /etc/etcd/tls/certs/peer-ca.pem \
        /etcd-etc/tls

    cp /etc/etcd/tls/certs/$ETCD_NAME-etcd-client.pem /etcd-etc/tls/etcd-client.pem
    cp /etc/etcd/tls/certs/$ETCD_NAME-etcd-peer.pem /etcd-etc/tls/etcd-peer.pem

    cp /etc/etcd/tls/keys/$ETCD_NAME-etcd-client-key.pem /etcd-etc/tls/etcd-client-key.pem
    cp /etc/etcd/tls/keys/$ETCD_NAME-etcd-peer-key.pem /etcd-etc/tls/etcd-peer-key.pem

    set +e
}

function create_manifest {
    sed -i -e 's#_ETCD_INITIAL_CLUSTER_STATE_#'$2'#g' /anchor-etcd/{{ .Values.service.name }}.yaml
    sed -i -e 's#_ETCD_INITIAL_CLUSTER_#'$1'#g' /anchor-etcd/{{ .Values.service.name }}.yaml

    cp /anchor-etcd/{{ .Values.service.name }}.yaml $MANIFEST_PATH
}

while true; do
    # TODO(mark-burnett) Need to monitor a file(s) when shutting down/starting
    # up so I don't try to take two actions on the node at once.
    {{- if .Values.bootstrapping.enabled  }}
    if [ -e /bootstrapping/{{ .Values.bootstrapping.filename }} ]; then
        # If the first node is starting, wait for it to become healthy
        end=$(($(date +%s) + {{ .Values.bootstrapping.timeout }}))
        while etcdctl member list | grep $POD_IP; do
            if ETCDCTL_ENDPOINTS=$CLIENT_ENDPOINT etcdctl endpoint health; then
                echo Member appears healthy, removing bootstrap file.
                rm /bootstrapping/{{ .Values.bootstrapping.filename }}
                break
            else
                now=$(date +%s)
                if [ $now -gt $end ]; then
                    echo Member did not start successfully before bootstrap timeout.  Deleting and trying again.
                    rm -f $MANIFEST_PATH
                    sleep {{ .Values.anchor.period }}
                    break
                fi
                sleep {{ .Values.anchor.period }}
            fi
        done
    fi

    if [ -e /bootstrapping/{{ .Values.bootstrapping.filename }} ]; then
        # Bootstrap the first node
        copy_certificates ${ETCD_NAME}
        ETCD_INITIAL_CLUSTER=${ETCD_NAME}=https://\$\(POD_IP\):{{ .Values.network.service_peer.target_port }}
        ETCD_INITIAL_CLUSTER_STATE=new
        create_manifest $ETCD_INITIAL_CLUSTER $ETCD_INITIAL_CLUSTER_STATE

        continue
    fi
    {{- end }}

    sleep {{ .Values.anchor.period }}

    if [ -e /tmp/stopped ]; then
        echo Stopping
        break
    fi

    if [ -e /tmp/stopping ]; then
        echo Waiting to stop..
        continue
    fi

    if [ ! -e $MANIFEST_PATH ]; then
        if ! etcdctl member list > /tmp/members; then
            echo Failed to locate existing cluster
            continue
        fi

        if ! grep $PEER_ENDPOINT /tmp/members; then
            if grep -v '\bstarted\b' /tmp/members; then
                echo Cluster does not appear fully online, waiting.
                continue
            fi

            # Add this member to the cluster
            etcdctl member add $HOSTNAME --peer-urls $PEER_ENDPOINT
        fi

        # If needed, drop the file in place
        if [ ! -e FILE ]; then
            # Refresh member list
            etcdctl member list > /tmp/members

            if grep $PEER_ENDPOINT /tmp/members; then
                copy_certificates ${ETCD_NAME}

                ETCD_INITIAL_CLUSTER=$(grep -v $PEER_ENDPOINT /tmp/members \
                    | awk -F ', ' '{ print $3 "=" $4 }' \
                    | tr '\n' ',' \
                    | sed "s;\$;$ETCD_NAME=https://\$\(POD_IP\):{{ .Values.network.service_peer.target_port }};")
                ETCD_INITIAL_CLUSTER_STATE=existing

                create_manifest $ETCD_INITIAL_CLUSTER $ETCD_INITIAL_CLUSTER_STATE
            fi
        fi
    fi
done
