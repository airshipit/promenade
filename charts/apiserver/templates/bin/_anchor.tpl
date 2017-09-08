#!/bin/sh

set -x

export MANIFEST_PATH=/host{{ .Values.anchor.kubelet.manifest_path }}/{{ .Values.service.name }}.yaml
export PKI_PATH=/host{{ .Values.apiserver.host_etc_path }}/pki

copy_certificates() {
    mkdir -p $PKI_PATH
    cp /certs/* /keys/* $PKI_PATH
}

create_manifest() {
    mkdir -p $(dirname $MANIFEST_PATH)
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
    - name: apiserver
      image: {{ .Values.images.apiserver }}
      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      command:
        - {{ .Values.apiserver.command }}
        - --authorization-mode=Node,RBAC
        - --advertise-address=\$(POD_IP)
        - --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,ResourceQuota,DefaultTolerationSeconds
        - --anonymous-auth=false
        - --bind-address=0.0.0.0
        - --secure-port={{ .Values.apiserver.port }}
        - --insecure-port=0
        - --apiserver-count={{ .Values.apiserver.replicas }}

        - --client-ca-file=/etc/kubernetes/apiserver/pki/cluster-ca.pem
        - --tls-cert-file=/etc/kubernetes/apiserver/pki/apiserver.pem
        - --tls-private-key-file=/etc/kubernetes/apiserver/pki/apiserver-key.pem

        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-certificate-authority=/etc/kubernetes/apiserver/pki/cluster-ca.pem
        - --kubelet-client-certificate=/etc/kubernetes/apiserver/pki/apiserver.pem
        - --kubelet-client-key=/etc/kubernetes/apiserver/pki/apiserver-key.pem

        - --etcd-servers={{ .Values.apiserver.etcd.endpoints }}
        - --etcd-cafile=/etc/kubernetes/apiserver/pki/etcd-client-ca.pem
        - --etcd-certfile=/etc/kubernetes/apiserver/pki/etcd-client.pem
        - --etcd-keyfile=/etc/kubernetes/apiserver/pki/etcd-client-key.pem

        - --allow-privileged=true

        - --service-cluster-ip-range={{ .Values.network.service_cidr }}
        - --service-account-key-file=/etc/kubernetes/apiserver/pki/service-account.pub

        - --v=5

      ports:
        - containerPort: 443
      volumeMounts:
        - name: etc
          mountPath: /etc/kubernetes/apiserver
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.apiserver.host_etc_path }}
EODOC
}

cleanup() {
    rm -f $MANIFEST_PATH
    rm -rf $PKI_PATH
}

while true; do
    if [ -e /tmp/stop ]; then
        echo Stopping
        cleanup
        break
    fi

    if [ ! -e $MANIFEST_PATH ]; then
        copy_certificates
        create_manifest
    fi

    sleep {{ .Values.anchor.period }}
done
