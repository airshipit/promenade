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

{{- $envAll := . }}
---
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.service.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{ .Values.service.name }}-service: enabled
{{ tuple $envAll "kubernetes" "apiserver" | include "helm-toolkit.snippets.kubernetes_metadata_labels" | indent 4 }}
spec:
  hostNetwork: true
  shareProcessNamespace: true
  containers:
    - name: apiserver
      image: {{ .Values.images.tags.apiserver }}
{{ tuple $envAll $envAll.Values.pod.resources.kubernetes_apiserver | include "helm-toolkit.snippets.kubernetes_resources" | indent 6 }}
      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: NODENAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: KUBECONFIG
          value: /etc/kubernetes/apiserver/kubeconfig.yaml

      command:
        {{- range .Values.command_prefix }}
        - {{ . }}
        {{- end }}
        - --advertise-address=$(POD_IP)
        - --anonymous-auth=false
        - --bind-address=0.0.0.0
        - --secure-port={{ .Values.network.kubernetes_apiserver.port }}
        - --insecure-port=0
        - --client-ca-file=/etc/kubernetes/apiserver/pki/cluster-ca.pem
        - --tls-cert-file=/etc/kubernetes/apiserver/pki/apiserver.pem
        - --tls-private-key-file=/etc/kubernetes/apiserver/pki/apiserver-key.pem
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-certificate-authority=/etc/kubernetes/apiserver/pki/cluster-ca.pem
        - --kubelet-client-certificate=/etc/kubernetes/apiserver/pki/kubelet-client.pem
        - --kubelet-client-key=/etc/kubernetes/apiserver/pki/kubelet-client-key.pem
        - --etcd-servers={{ .Values.apiserver.etcd.endpoints }}
        - --etcd-cafile=/etc/kubernetes/apiserver/pki/etcd-client-ca.pem
        - --etcd-certfile=/etc/kubernetes/apiserver/pki/etcd-client.pem
        - --etcd-keyfile=/etc/kubernetes/apiserver/pki/etcd-client-key.pem
        - --allow-privileged=true
        - --service-account-key-file=/etc/kubernetes/apiserver/pki/service-account.pub

      ports:
        - containerPort: {{ .Values.network.kubernetes_apiserver.port }}

      readinessProbe:
        exec:
          command:
          - /bin/bash
          - -c
          - |-
            if [ ! -f /etc/kubernetes/apiserver/pki/apiserver-both.pem ]; then
              cat /etc/kubernetes/apiserver/pki/apiserver-key.pem /etc/kubernetes/apiserver/pki/apiserver.pem > /etc/kubernetes/apiserver/pki/apiserver-both.pem
            fi
            echo -e 'GET /healthz HTTP/1.0\r\n' | socat - openssl:localhost:{{ .Values.network.kubernetes_apiserver.port }},cert=/etc/kubernetes/apiserver/pki/apiserver-both.pem,cafile=/etc/kubernetes/apiserver/pki/cluster-ca.pem | grep '200 OK'
            exit $?
        initialDelaySeconds: 10
        periodSeconds: 5
        timeoutSeconds: 5

      livenessProbe:
        exec:
          command:
          - /bin/bash
          - -c
          - |-
            kubectl get nodes ${NODENAME} | grep ${NODENAME}
            exit $?
        failureThreshold: 3
        initialDelaySeconds: 60
        periodSeconds: 10
        successThreshold: 1
        timeoutSeconds: 10

      volumeMounts:
        - name: etc
          mountPath: /etc/kubernetes/apiserver
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.apiserver.host_etc_path }}
