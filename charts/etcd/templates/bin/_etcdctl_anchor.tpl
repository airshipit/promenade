#!/bin/sh
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
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
TEMP_MANIFEST=/tmp/etcd.yaml

sync_file () {
    if ! cmp "$1" "$2"; then
        cp -f "$1" "$2"
    fi
}

sync_certificates () {
    mkdir -p /etcd-etc/tls
    sync_file /etc/etcd/tls/certs/client-ca.pem /etcd-etc/tls/client-ca.pem
    sync_file /etc/etcd/tls/certs/peer-ca.pem /etcd-etc/tls/peer-ca.pem
    sync_file "/etc/etcd/tls/certs/${ETCD_NAME}-etcd-client.pem" /etcd-etc/tls/etcd-client.pem
    sync_file "/etc/etcd/tls/certs/${ETCD_NAME}-etcd-peer.pem" /etcd-etc/tls/etcd-peer.pem
    sync_file "/etc/etcd/tls/keys/${ETCD_NAME}-etcd-client-key.pem" /etcd-etc/tls/etcd-client-key.pem
    sync_file "/etc/etcd/tls/keys/${ETCD_NAME}-etcd-peer-key.pem" /etcd-etc/tls/etcd-peer-key.pem
}

create_manifest () {
    WIP=/tmp/wip-manifest.yaml
    cp -f /anchor-etcd/{{ .Values.service.name }}.yaml $WIP
    sed -i -e 's#_ETCD_INITIAL_CLUSTER_STATE_#'$2'#g' $WIP
    sed -i -e 's#_ETCD_INITIAL_CLUSTER_#'$1'#g' $WIP
    sync_file "$WIP" "$3"
}

sync_configuration () {
    sync_certificates
    ETCD_INITIAL_CLUSTER=$(grep -v $PEER_ENDPOINT "$1" \
        | awk -F ', ' '{ print $3 "=" $4 }' \
        | tr '\n' ',' \
        | sed "s;\$;$ETCD_NAME=https://\$\(POD_IP\):{{ .Values.network.service_peer.target_port }};")
    ETCD_INITIAL_CLUSTER_STATE=existing
    create_manifest "$ETCD_INITIAL_CLUSTER" "$ETCD_INITIAL_CLUSTER_STATE" "$TEMP_MANIFEST"
    sync_file "${TEMP_MANIFEST}" "${MANIFEST_PATH}"
    chmod go-rwx "${MANIFEST_PATH}"
}

cleanup_host () {
    rm -f $MANIFEST_PATH
    rm -rf /etcd-etc/tls/
    rm -rf /etcd-data/*
    firstrun=true
}

firstrun=true
saddness_duration=0
while true; do
    date
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
        sync_certificates
        ETCD_INITIAL_CLUSTER=${ETCD_NAME}=https://\$\(POD_IP\):{{ .Values.network.service_peer.target_port }}
        ETCD_INITIAL_CLUSTER_STATE=new
        create_manifest "$ETCD_INITIAL_CLUSTER" "$ETCD_INITIAL_CLUSTER_STATE" "$MANIFEST_PATH"
        sleep {{ .Values.anchor.period }}
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
    etcdctl member list > /tmp/members
    if ! grep $PEER_ENDPOINT /tmp/members; then
        # If this member is not in the cluster, try to add it.
        if grep -v '\bstarted\b' /tmp/members; then
            echo Cluster does not appear fully online, waiting.
            continue
        fi
        # Add this member to the cluster
        if ! etcdctl member add $HOSTNAME --peer-urls $PEER_ENDPOINT; then
            echo Failed to add $HOSTNAME to member list.  Waiting.
            continue
        fi
        echo Successfully added $HOSTNAME to cluster members.
        # Refresh member list so we start with the right configuration.
        if ! etcdctl member list > /tmp/members; then
          echo Could not get a member list, trying again.
          continue
        fi
    elif grep $PEER_ENDPOINT /tmp/members | grep '\bunstarted\b'; then
        # This member is in the cluster but not started
        if [ $saddness_duration -ge {{ .Values.anchor.saddness_threshold }} ]
        then
          # We have surpassed the sadness duration, remove the member and try re-adding
          memberid=$(grep $PEER_ENDPOINT /tmp/members | awk -F ',' '{print $1}')
          echo "Removing $memberid from etcd cluster to recreate."
          if etcdctl member remove "$memberid"; then
            cleanup_host
          else
            echo "ERROR: Attempted recreate member and failed!!!"
          fi
          continue
        else
          saddness_duration=$(($saddness_duration+1))
        fi
    fi
    if $firstrun; then
        sync_configuration /tmp/members
        firstrun=false
    fi
    if ! ETCDCTL_ENDPOINTS=$CLIENT_ENDPOINT etcdctl endpoint health; then
        # If not health, sleeps before checking again and then updating configs.
        echo Member is not healthy, sleeping before checking again.
        sleep {{ .Values.anchor.health_wait_period }}
        if ! ETCDCTL_ENDPOINTS=$CLIENT_ENDPOINT etcdctl endpoint health; then
            # If still not healthy updates the configs.
            echo Member is not healthy, syncing configurations.
            sync_configuration /tmp/members
            continue
        else
          saddness_duration=0
        fi
    else
      saddness_duration=0
    fi
done
