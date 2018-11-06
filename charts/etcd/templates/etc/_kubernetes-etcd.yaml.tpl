{{/*
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
*/}}

{{- $envAll := . }}
# Strip off "etcd" from service name to get the application name
# Note that application can either be kubernetes or calico for now
# and may expand in scope in the future
{{- $applicationName := .Values.service.name | replace "-etcd" "" }}
---
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.service.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{ .Values.service.name }}-service: enabled
{{ tuple $envAll $applicationName "etcd" | include "helm-toolkit.snippets.kubernetes_metadata_labels" | indent 4 }}
  annotations:
    {{ tuple $envAll | include "helm-toolkit.snippets.release_uuid" }}
spec:
  hostNetwork: true
  containers:
    - name: etcd
      image: {{ .Values.images.tags.etcd }}
      imagePullPolicy: {{ .Values.images.pull_policy }}
{{ tuple $envAll $envAll.Values.pod.resources.etcd_pod | include "helm-toolkit.snippets.kubernetes_resources" | indent 6 }}
      env:
        - name: ETCD_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
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
          value: https://$(POD_IP):{{ .Values.network.service_client.target_port }}
        - name: ETCD_INITIAL_ADVERTISE_PEER_URLS
          value: https://$(POD_IP):{{ .Values.network.service_peer.target_port }}
        - name: ETCD_INITIAL_CLUSTER_TOKEN
          value: {{ .Values.service.name }}-init-token
        - name: ETCD_LISTEN_CLIENT_URLS
          value: https://0.0.0.0:{{ .Values.network.service_client.target_port }}
        - name: ETCD_LISTEN_PEER_URLS
          value: https://0.0.0.0:{{ .Values.network.service_peer.target_port }}
        - name: ETCD_INITIAL_CLUSTER_STATE
          value: _ETCD_INITIAL_CLUSTER_STATE_
        - name: ETCD_INITIAL_CLUSTER
          value: _ETCD_INITIAL_CLUSTER_
        - name: ETCDCTL_API
          value: '3'
        - name: ETCDCTL_DIAL_TIMEOUT
          value: 3s
        - name: ETCDCTL_ENDPOINTS
          value: https://127.0.0.1:{{ .Values.network.service_client.target_port }}
        - name: ETCDCTL_CACERT
          value: $(ETCD_TRUSTED_CA_FILE)
        - name: ETCDCTL_CERT
          value: $(ETCD_CERT_FILE)
        - name: ETCDCTL_KEY
          value: $(ETCD_KEY_FILE)
        - name: CLIENT_ENDPOINT
          value: https://$(POD_IP):{{ .Values.network.service_client.target_port }}
        - name: PEER_ENDPOINT
          value: https://$(POD_IP):{{ .Values.network.service_peer.target_port }}
        - name: MANIFEST_PATH
          value: /manifests/{{ .Values.service.name }}.yaml
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
