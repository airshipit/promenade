# Copyright 2025 AT&T Intellectual Property.  All other rights reserved.
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
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: {{ .Values.cluster_config.kubernetesVersion }}
apiServer:
  extraArgs:
    - name: etcd-servers
      value: "{{ .Values.cluster_config.apiserver.etcd_endpoints }}"
    - name: v
      value: "{{ .Values.cluster_config.apiserver.log_level }}"
{{- if .Values.cluster_config.apiserver.extraArgs }}
{{ toYaml .Values.cluster_config.apiserver.extraArgs | indent 4 }}
{{- end }}
{{- if .Values.cluster_config.apiserver.extraVolumes }}
  extraVolumes:
{{ toYaml .Values.cluster_config.apiserver.extraVolumes | indent 4 }}
{{- end }}
certificatesDir: {{ .Values.cluster_config.certificatesDir }}
clusterName: {{ .Values.cluster_config.clusterName }}
controlPlaneEndpoint: "{{ .Values.cluster_config.controlPlaneEndpoint }}"
controllerManager:
  extraArgs:
    - name: v
      value: "{{ .Values.cluster_config.controller_manager.log_level }}"
{{- if .Values.cluster_config.controller_manager.extraArgs }}
{{ toYaml .Values.cluster_config.controller_manager.extraArgs | indent 4 }}
{{- end }}
{{- if .Values.cluster_config.controller_manager.extraVolumes }}
  extraVolumes:
{{ toYaml .Values.cluster_config.controller_manager.extraVolumes | indent 4 }}
{{- end }}
featureGates:
  NodeLocalCRISocket: false
dns:
  disabled: true
encryptionAlgorithm: RSA-2048
etcd:
  local:
    imageRepository: "{{ .Values.cluster_config.etcd.imageRepository }}"
    dataDir: "{{ .Values.cluster_config.etcd.dataDir }}"
    extraArgs:
{{- if .Values.cluster_config.etcd.initial_cluster }}
      - name: initial-cluster
        value: "{{ .Values.cluster_config.etcd.initial_cluster }}"
{{- end }}
{{- if .Values.cluster_config.etcd.initial_cluster_state }}
      - name: initial-cluster-state
        value: "{{ .Values.cluster_config.etcd.initial_cluster_state }}"
{{- end }}
{{- if .Values.cluster_config.etcd.initial_cluster_token }}
      - name: initial-cluster-token
        value: "{{ .Values.cluster_config.etcd.initial_cluster_token }}"
{{- end }}
      - name: log-level
        value: "{{ .Values.cluster_config.etcd.log_level }}"
{{- if .Values.cluster_config.etcd.extraArgs }}
{{ toYaml .Values.cluster_config.etcd.extraArgs | indent 6 }}
{{- end }}
{{- if .Values.cluster_config.etcd.extraEnvs }}
    extraEnvs:
{{ toYaml .Values.cluster_config.etcd.extraEnvs | indent 6 }}
{{- end }}
imageRepository: {{ .Values.cluster_config.imageRepository }}
networking:
{{ toYaml .Values.cluster_config.networking | indent 2 }}
proxy:
  disabled: true
scheduler:
  extraArgs:
    - name: v
      value: "{{ .Values.cluster_config.scheduler.log_level }}"
{{- if .Values.cluster_config.scheduler.extraArgs }}
{{ toYaml .Values.cluster_config.scheduler.extraArgs | indent 4 }}
{{- end }}
{{- if .Values.cluster_config.scheduler.extraVolumes }}
  extraVolumes:
{{ toYaml .Values.cluster_config.scheduler.extraVolumes | indent 4 }}
{{- end }}
