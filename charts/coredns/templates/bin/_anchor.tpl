#!/bin/sh

{{- $envAll := . }}

set -x

export MANIFEST_PATH=/host{{ .Values.anchor.kubelet.manifest_path }}/{{ .Values.service.name }}.yaml
export ETC_PATH=/host{{ .Values.coredns.host_etc_path }}
TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token
CA_CERT_PATH=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

copy_etc_files() {
    mkdir -p $ETC_PATH/zones
    cp /configmap/* /secret/* $ETC_PATH
    create_corefile
}

create_corefile() {
    cat <<EOCOREFILE > $ETC_PATH/Corefile
promenade {
    file /etc/coredns/zones/promenade
    loadbalance
    errors stdout
    log stdout
}

{{ .Values.coredns.cluster_domain }} {
    kubernetes {
        endpoint https://{{ .Values.network.kubernetes_netloc }}
        tls /etc/coredns/coredns.pem /etc/coredns/coredns-key.pem /etc/coredns/cluster-ca.pem
    }
    loadbalance
    cache {{ .Values.coredns.cache.ttl }}
    errors stdout
    log stdout
}

. {
    {{- if .Values.coredns.upstream_nameservers }}
    proxy .  {{- range .Values.coredns.upstream_nameservers }} {{ . -}}{{- end }}
    {{- end }}
    errors stdout
    log stdout
}
EOCOREFILE
}

create_manifest() {
    mkdir -p $(dirname $MANIFEST_PATH)
# XXX liveness/readiness probes
    cat <<EODOC > $MANIFEST_PATH
---
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.service.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{ .Values.service.name }}-service: enabled
    anchor-managed: enabled
spec:
  hostNetwork: true
  containers:
    - name: coredns
      image: {{ .Values.images.coredns }}
      command:
        - /coredns
        - -conf
        - /etc/coredns/Corefile
      volumeMounts:
        - name: etc
          mountPath: /etc/coredns
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.coredns.host_etc_path }}
EODOC
}

update_managed_zones() {
{{- range .Values.coredns.zones }}

FILENAME="$ETC_PATH/zones/{{ .name }}"
NEXT_FILENAME="${FILENAME}-next"
SUCCESS=1
NOW=$(date +%s)

# Add Header
cat <<EOBIND > $NEXT_FILENAME
\$ORIGIN {{ .name }}.
{{ .name }}. IN SOA @ root $NOW 3h 15m 1w 1d

EOBIND
{{ range .services }}
# Don't accidentally log service account token
set +x
SERVICE_IPS=$(kubectl \
    --server https://{{ $envAll.Values.network.kubernetes_netloc }} \
    --certificate-authority $CA_CERT_PATH \
    --token $(cat $TOKEN_PATH) \
    -n {{ .service.namespace }} \
        get ep {{ .service.name }} \
            -o 'jsonpath={.subsets[*].addresses[*].ip}')
set -x
if [ "x$SERVICE_IPS" != "x" ]; then
    for IP in $SERVICE_IPS; do
        echo {{ .bind_name }} IN A $IP >> $NEXT_FILENAME
    done
else
    echo Failed to upate zone file for {{ .name }}
    SUCCESS=0
fi
{{- end }}

if [ $SUCCESS = 1 ]; then
    echo Replacing zone file $FILENAME
    mv $NEXT_FILENAME $FILENAME
fi
{{- end }}
}

copy_etc_files
create_manifest

while true; do
    update_managed_zones

    sleep {{ .Values.anchor.period }}
done
