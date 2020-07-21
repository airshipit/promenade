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

{{- define "kubernetes_apiserver.key_concat" -}}
    {{- range $encProv := .Values.conf.encryption_provider.content.resources -}}
      {{- if hasKey (index $encProv "providers" 0) "identity" -}}
        {{- printf "%s" (index $encProv "providers" 0 "identity") -}}
      {{- else if hasKey (index $encProv "providers" 0) "secretbox" -}}
        {{- printf "%s" (index $encProv "providers" 0 "secretbox" "keys" 0 "secret") -}}
      {{- else if hasKey (index $encProv "providers" 0) "aescbc" -}}
        {{- printf "%s" (index $encProv "providers" 0 "aescbc" "keys" 0 "secret") -}}
      {{- else if hasKey (index $encProv "providers" 0) "aesgcm" -}}
        {{- printf "%s" (index $encProv "providers" 0 "aesgcm" "keys" 0 "secret") -}}
      {{- end -}}
    {{- end -}}
{{- end -}}


{{- define "kubernetes_apiserver.key_annotation" -}}
  {{- if and (.Values.conf) (hasKey .Values.conf "encryption_provider") -}}
    {{- $encKey := ( . | include "kubernetes_apiserver.key_concat") -}}
{{ .Values.const.encryption_annotation | quote }}: {{ sha256sum $encKey | quote }}
  {{- end -}}
{{- end -}}


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
  annotations:
    {{ $envAll | include "kubernetes_apiserver.key_annotation" }}
    {{ tuple $envAll | include "helm-toolkit.snippets.release_uuid" }}
{{- dict "envAll" $envAll "podName" "apiserver" "containerNames" (list "apiserver") | include "helm-toolkit.snippets.kubernetes_mandatory_access_control_annotation" | indent 4 }}
spec:
{{ dict "envAll" $envAll "application" "apiserver" | include "helm-toolkit.snippets.kubernetes_pod_security_context" | indent 2 }}
  hostNetwork: true
  shareProcessNamespace: true
  containers:
    - name: apiserver
      image: {{ .Values.images.tags.apiserver }}
{{ tuple $envAll $envAll.Values.pod.resources.kubernetes_apiserver | include "helm-toolkit.snippets.kubernetes_resources" | indent 6 }}
{{ dict "envAll" $envAll "application" "apiserver" "container" "apiserver" | include "helm-toolkit.snippets.kubernetes_container_security_context" | indent 6 }}
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
        - name: APISERVER_PORT
          value: {{ .Values.network.kubernetes_apiserver.port | quote }}
        - name: ETCD_ENDPOINTS
          value: {{ .Values.apiserver.etcd.endpoints | quote }}

      command:
        {{- range .Values.const.command_prefix }}
        - {{ . }}
        {{- end }}
        {{- range .Values.apiserver.arguments }}
        - {{ . }}
        {{- end }}
        {{- range $key, $val := .Values.conf }}
        {{- if hasKey $val "command_options" }}
        {{- range $val.command_options }}
        - {{ . }}
        {{- end }}
        {{- end }}
        {{- end }}
        {{- $acceptable_keys := list "tls-min-version" "tls-cipher-suites" }}
        {{- range $key, $val := .Values.apiserver.tls }}
        {{- if has $key  $acceptable_keys }}
        - --{{ $key }}={{ $val }}
        {{- end }}
        {{- end }}
        {{- if .Values.apiserver.logging.log_level }}
        - --v={{ .Values.apiserver.logging.log_level }}
        {{- end }}
      ports:
        - containerPort: {{ .Values.network.kubernetes_apiserver.port }}

      readinessProbe:
        exec:
          command:
          - /bin/bash
          - -c
          - |-
            if [ ! -f /etc/kubernetes/apiserver/pki/apiserver-both.pem ]; then
              cat /etc/kubernetes/apiserver/pki/apiserver-key.pem <(echo) /etc/kubernetes/apiserver/pki/apiserver.pem > /etc/kubernetes/apiserver/pki/apiserver-both.pem
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
