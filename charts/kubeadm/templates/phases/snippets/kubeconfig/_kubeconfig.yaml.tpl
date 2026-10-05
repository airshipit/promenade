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

{{- $envAll := . -}}

---
apiVersion: v1
clusters:
- cluster:
    server: https://{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}
    certificate-authority: ${CERT_AUTH}
  name: {{ $envAll.Values.kubeconfig.clusterName }}
contexts:
- context:
    cluster: {{ $envAll.Values.kubeconfig.clusterName  }}
    user: ${USER}
  name: ${USER}@{{ $envAll.Values.kubeconfig.clusterName }}
current-context: ${USER}@{{ $envAll.Values.kubeconfig.clusterName  }}
kind: Config
preferences: {}
users:
- name: ${USER}
  user:
    client-certificate: ${CLIENT_CERT}
    client-key: ${CLIENT_KEY}
