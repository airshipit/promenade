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
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: {{ .Values.kubernetes.version }}
apiServer:
{{- if .Values.apiserver.extraArgs }}
  extraArgs:
{{ toYaml .Values.apiserver.extraArgs | indent 4 }}
{{- end }}
{{- if .Values.apiserver.extraVolumes }}
  extraVolumes:
{{ toYaml .Values.apiserver.extraVolumes | indent 4 }}
{{- end }}
caCertificateValidityPeriod: 87600h0m0s
certificateValidityPeriod: 8760h0m0s
certificatesDir: "/etc/kubernetes/pki"
clusterName: kubernetes
controlPlaneEndpoint: "127.0.0.1:6553"
controllerManager:
  extraArgs:
  - name: node-monitor-period
    value: "5s"
  - name: node-monitor-grace-period
    value: "20s"
  - name: terminated-pod-gc-threshold
    value: "1000"
  - name: configure-cloud-routes
    value: "false"
  - name: v
    value: "2"
  extraVolumes: []
dns:
  disabled: true
encryptionAlgorithm: RSA-2048
etcd:
{{ toYaml .Values.etcd | indent 2 }}
imageRepository: docker-open-nc.zc1.cti.att.com/upstream-local/kubernetes
networking:
  dnsDomain: cluster.local
  podSubnet: "10.97.0.0/16"
  serviceSubnet: "10.96.0.0/16"
proxy:
  disabled: true
scheduler:
  extraArgs:
  - name: secure-port
    value: "10259"
  - name: v
    value: "2"
  extraVolumes:
  - hostPath: "/etc/kubernetes/pki"
    mountPath: "/etc/kubernetes/pki"
    name: pki-certs
    pathType: DirectoryOrCreate
