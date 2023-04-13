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
---
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.service.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{ .Values.service.name }}-service: enabled
{{ tuple $envAll "kubernetes" "scheduler" | include "helm-toolkit.snippets.kubernetes_metadata_labels" | indent 4 }}
  annotations:
    created-by: ANCHOR_POD
    {{ tuple $envAll | include "helm-toolkit.snippets.release_uuid" }}
{{ dict "envAll" $envAll "podName" "scheduler" "containerNames" (list "scheduler") | include "helm-toolkit.snippets.kubernetes_mandatory_access_control_annotation" | indent 4 }}
spec:
{{ dict "envAll" $envAll "application" "scheduler" | include "helm-toolkit.snippets.kubernetes_pod_security_context" | indent 2 }}
  hostNetwork: true
  containers:
    - name: scheduler
      image: {{ .Values.images.tags.scheduler }}
{{ tuple $envAll $envAll.Values.pod.resources.scheduler_pod | include "helm-toolkit.snippets.kubernetes_resources" | indent 6 }}
{{ dict "envAll" $envAll "application" "scheduler" "container" "scheduler" | include "helm-toolkit.snippets.kubernetes_container_security_context" | indent 6 }}
      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      command:
        {{- range .Values.command_prefix }}
        - {{ . }}
        {{- end }}
        - --authentication-kubeconfig=/etc/kubernetes/scheduler/kubeconfig.yaml
        - --authorization-kubeconfig=/etc/kubernetes/scheduler/kubeconfig.yaml
        - --bind-address=127.0.0.1
        - --secure-port={{ .Values.network.kubernetes_scheduler.port }}
        - --leader-elect=true
        - --kubeconfig=/etc/kubernetes/scheduler/kubeconfig.yaml
        {{- if .Values.scheduler.logging.log_level }}
        - --v={{ .Values.scheduler.logging.log_level }}
        {{- end }}

      readinessProbe:
        httpGet:
          host: 127.0.0.1
          path: /healthz
          port: {{ .Values.network.kubernetes_scheduler.port }}
          scheme: HTTPS
        initialDelaySeconds: 10
        periodSeconds: 5
        timeoutSeconds: 5

      livenessProbe:
        failureThreshold: 2
        httpGet:
          host: 127.0.0.1
          path: /healthz
          port: {{ .Values.network.kubernetes_scheduler.port }}
          scheme: HTTPS
        initialDelaySeconds: 15
        periodSeconds: 10
        successThreshold: 1
        timeoutSeconds: 15

      volumeMounts:
        - name: etc
          mountPath: /etc/kubernetes/scheduler
          defaultMode: 0444
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.scheduler.host_etc_path }}
