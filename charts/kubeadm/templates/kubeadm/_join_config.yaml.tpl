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
kind: JoinConfiguration
caCertPath: {{ .Values.join_config.caCertPath }}
controlPlane:
  localAPIEndpoint:
    advertiseAddress: "${HOST_IP}"
    bindPort: {{ .Values.join_config.controlPlane.localAPIEndpoint.bindPort }}
discovery:
  file:
    kubeConfigPath: {{ .Values.join_config.discovery.file.kubeConfigPath }}
nodeRegistration:
  imagePullPolicy: {{ .Values.join_config.nodeRegistration.imagePullPolicy }}
  imagePullSerial: {{ .Values.join_config.nodeRegistration.imagePullSerial }}
  name: ${NODE_NAME}
  ignorePreflightErrors:
{{ toYaml .Values.join_config.nodeRegistration.ignorePreflightErrors | indent 2 }}
  taints: []
skipPhases:
{{ toYaml .Values.join_config.skipPhases }}
patches:
  directory: {{ .Values.join_config.patches.directory }}
