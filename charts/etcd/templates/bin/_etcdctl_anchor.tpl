#!/bin/sh

set -x

export CLIENT_ENDPOINT=https://$POD_IP:{{ .Values.service.client.target_port }}
export PEER_ENDPOINT=https://$POD_IP:{{ .Values.service.peer.target_port }}
export MANIFEST_PATH=/manifests/{{ .Values.service.name }}.yaml

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
    ETCD_INITIAL_CLUSTER=$1
    ETCD_INITIAL_CLUSTER_STATE=$2
    cat <<EODOC > $MANIFEST_PATH
---
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.service.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{ .Values.service.name }}-service: enabled
spec:
  hostNetwork: true
  containers:
    - name: etcd
      image: {{ .Values.images.etcd }}
      env:
        - name: ETCD_NAME
          value: $ETCD_NAME
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: ETCD_CLIENT_CERT_AUTH
          value: "true"
        - name: ETCD_PEER_CLIENT_CERT_AUTH
          value: "true"
        - name: ETCD_DATA_DIR
          value: /var/lib/etcd
        - name: ETCD_TRUSTED_CA_FILE
          value: /etc/etcd/tls/client-ca.pem
        - name: ETCD_CERT_FILE
          value: /etc/etcd/tls/etcd-client.pem
        - name: ETCD_STRICT_RECONFIG_CHECK
          value: "true"
        - name: ETCD_KEY_FILE
          value: /etc/etcd/tls/etcd-client-key.pem
        - name: ETCD_PEER_TRUSTED_CA_FILE
          value: /etc/etcd/tls/peer-ca.pem
        - name: ETCD_PEER_CERT_FILE
          value: /etc/etcd/tls/etcd-peer.pem
        - name: ETCD_PEER_KEY_FILE
          value: /etc/etcd/tls/etcd-peer-key.pem
        - name: ETCD_ADVERTISE_CLIENT_URLS
          value: https://\$(POD_IP):{{ .Values.service.client.target_port }}
        - name: ETCD_INITIAL_ADVERTISE_PEER_URLS
          value: https://\$(POD_IP):{{ .Values.service.peer.target_port }}
        - name: ETCD_INITIAL_CLUSTER_TOKEN
          value: {{ .Values.service.name }}-init-token
        - name: ETCD_LISTEN_CLIENT_URLS
          value: https://0.0.0.0:{{ .Values.service.client.target_port }}
        - name: ETCD_LISTEN_PEER_URLS
          value: https://0.0.0.0:{{ .Values.service.peer.target_port }}
        - name: ETCD_INITIAL_CLUSTER_STATE
          value: $ETCD_INITIAL_CLUSTER_STATE
        - name: ETCD_INITIAL_CLUSTER
          value: $ETCD_INITIAL_CLUSTER
        - name: ETCDCTL_API
          value: '3'
        - name: ETCDCTL_DIAL_TIMEOUT
          value: 3s
        - name: ETCDCTL_ENDPOINTS
          value: https://127.0.0.1:{{ .Values.service.client.target_port }}
        - name: ETCDCTL_CACERT
          value: \$(ETCD_TRUSTED_CA_FILE)
        - name: ETCDCTL_CERT
          value: \$(ETCD_CERT_FILE)
        - name: ETCDCTL_KEY
          value: \$(ETCD_KEY_FILE)
      volumeMounts:
        - name: data
          mountPath: /var/lib/etcd
        - name: etc
          mountPath: /etc/etcd
  volumes:
    - name: data
      hostPath:
        path: {{ .Values.etcd.host_data_path }}
    - name: etc
      hostPath:
        path: {{ .Values.etcd.host_etc_path }}
...
EODOC
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
        ETCD_INITIAL_CLUSTER=${ETCD_NAME}=$PEER_ENDPOINT
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
                    | sed "s;\$;$ETCD_NAME=$PEER_ENDPOINT;")
                ETCD_INITIAL_CLUSTER_STATE=existing

                create_manifest $ETCD_INITIAL_CLUSTER $ETCD_INITIAL_CLUSTER_STATE
            fi
        fi
    fi
done
