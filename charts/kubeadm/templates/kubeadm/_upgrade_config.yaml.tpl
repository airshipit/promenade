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
kind: UpgradeConfiguration
node:
  certificateRenewal: {{ .Values.upgrade_config.node.certificateRenewal }}
  dryRun: false
  etcdUpgrade: false
  ignorePreflightErrors:
{{ toYaml .Values.upgrade_config.node.ignorePreflightErrors | indent 2 }}
  patches:
    directory: {{ .Values.upgrade_config.node.patches.directory }}
  skipPhases:
{{ toYaml .Values.upgrade_config.node.skipPhases | indent 2 }}
  imagePullPolicy: {{ .Values.upgrade_config.node.imagePullPolicy }}
  imagePullSerial: {{ .Values.upgrade_config.node.imagePullSerial }}
