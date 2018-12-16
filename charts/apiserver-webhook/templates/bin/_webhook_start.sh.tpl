#!/bin/sh

{{/*
Copyright 2018 The Openstack-Helm Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

set -xe

SERVER_CERT_FILE=${SERVER_CERT_FILE:-"/etc/webhook_apiserver/pki/tls.crt"}
SERVER_KEY_FILE=${SERVER_KEY_FILE:-"/etc/webhook_apiserver/pki/tls.key"}
POLICY_FILE=${POLICY_FILE:-"/etc/webhook_apiserver/policy.json"}
SERVER_PORT=${SERVER_PORT:-"8443"}
KEYSTONE_CA_FILE=${KEYSTONE_CA_FILE:-"/etc/webhook_apiserver/pki/keystone.pem"}

exec /bin/k8s-keystone-auth \
  --v 5 \
  --tls-cert-file "${SERVER_CERT_FILE}" \
  --tls-private-key-file "${SERVER_KEY_FILE}" \
  --keystone-policy-file "${POLICY_FILE}" \
  --listen "127.0.0.1:${SERVER_PORT}" \
{{- if hasKey .Values.certificates "keystone" }}
  --keystone-ca-file "${KEYSTONE_CA_FILE}" \
{{- end }}
  --keystone-url {{ tuple "identity" "internal" "api" . | include "helm-toolkit.endpoints.keystone_endpoint_uri_lookup" }}

