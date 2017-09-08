#!/bin/sh

set -x

export MANIFEST_PATH=/host{{ .Values.anchor.kubelet.manifest_path }}/{{ .Values.service.name }}.yaml
export ETC_PATH=/host{{ .Values.scheduler.host_etc_path }}

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
    - name: scheduler
      image: {{ .Values.images.scheduler }}
      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      command:
        - {{ .Values.scheduler.command }}
        - --leader-elect=true
        - --kubeconfig=/etc/kubernetes/scheduler/kubeconfig.yaml
        - --v=5

      volumeMounts:
        - name: etc
          mountPath: /etc/kubernetes/scheduler
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.scheduler.host_etc_path }}
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
