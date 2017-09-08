#!/bin/sh

set -x

export MANIFEST_PATH=/host{{ .Values.anchor.kubelet.manifest_path }}/{{ .Values.service.name }}.yaml
export ETC_PATH=/host{{ .Values.controller_manager.host_etc_path }}

copy_etc_files() {
    mkdir -p $ETC_PATH
    cp /configmap/* /secret/* $ETC_PATH
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
    - name: controller-manager
      image: {{ .Values.images.controller_manager }}
      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      command:
        - {{ .Values.controller_manager.command }}
        - --allocate-node-cidrs=true
        - --cluster-cidr={{ .Values.network.pod_cidr }}
        - --configure-cloud-routes=false
        - --leader-elect=true
        - --node-monitor-period={{ .Values.controller_manager.node_monitor_period }}
        - --node-monitor-grace-period={{ .Values.controller_manager.node_monitor_grace_period }}
        - --pod-eviction-timeout={{ .Values.controller_manager.pod_eviction_timeout }}
        - --kubeconfig=/etc/kubernetes/controller-manager/kubeconfig.yaml
        - --root-ca-file=/etc/kubernetes/controller-manager/cluster-ca.pem
        - --service-account-private-key-file=/etc/kubernetes/controller-manager/service-account.priv
        - --service-cluster-ip-range={{ .Values.network.service_cidr }}
        - --use-service-account-credentials=true

        - --v=5

      volumeMounts:
        - name: etc
          mountPath: /etc/kubernetes/controller-manager
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.controller_manager.host_etc_path }}
EODOC
}

cleanup() {
    rm -f $MANIFEST_PATH
    rm -rf $ETC_PATH
}

while true; do
    if [ -e /tmp/stop ]; then
        echo Stopping
        cleanup
        break
    fi

    if [ ! -e $MANIFEST_PATH ]; then
        copy_etc_files
        create_manifest
    fi

    sleep {{ .Values.anchor.period }}
done
