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
kind: JoinConfiguration
caCertPath: /etc/kubernetes/pki/ca.crt
controlPlane:
  localAPIEndpoint:
    advertiseAddress: "${HOST_IP}"
    bindPort: {{ .Values.network.kubernetes_apiserver.port }}
discovery:
  file:
    kubeConfigPath: /etc/kubernetes/admin.conf
nodeRegistration:
  imagePullPolicy: Always
  imagePullSerial: false
  name: ${NODE_NAME}
  ignorePreflightErrors:
  - Service-Kubelet
  - FileAvailable--etc-kubernetes-kubelet.conf
  - SystemVerification
  - Port-10250
  - Port-6443
  - Port-10259
  - Port-10257
  - Port-2379
  - Port-2380
  - DirAvailable--var-lib-etcd
  taints: []
skipPhases:
{{ toYaml .Values.kubeadm.join_config.skip_phases }}
patches:
  directory: /etc/kubernetes/kubeadm/patches
