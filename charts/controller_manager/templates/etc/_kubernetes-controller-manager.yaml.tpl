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
      image: {{ .Values.images.tags.controller_manager }}
      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      # NOTE: We will not expose parameters that should take on fixed values
      # in the values.yaml as these parameters should not be changed by user(s).
      command:
        {{- range .Values.command_prefix }}
        - {{ . }}
        {{- end }}
        - --configure-cloud-routes=false
        - --leader-elect=true
        - --kubeconfig=/etc/kubernetes/controller-manager/kubeconfig.yaml
        - --root-ca-file=/etc/kubernetes/controller-manager/cluster-ca.pem
        - --service-account-private-key-file=/etc/kubernetes/controller-manager/service-account.priv
        - --use-service-account-credentials=true
        - --v=5

      volumeMounts:
        - name: etc
          mountPath: /etc/kubernetes/controller-manager
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.controller_manager.host_etc_path }}
