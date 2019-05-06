#!/bin/bash
# Copyright 2019 AT&T Intellectual Property.  All other rights reserved.
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
set -ex

TEMP_DIR=$(mktemp -d)
ANNOTATION_NAME="airshipit.org/encryption_key"

get_service_endpoints() {
  ns="$1"
  svc="$2"
  kubectl -n $ns get endpoints -o json $svc | jq '.subsets[0].addresses' | jq '.[] | .targetRef.name' -r

}

get_pod_annotation() {
  ns="$1"
  pod_name="$2"
  kubectl -n $ns get pod "$pod_name" -o json | jq ".metadata.annotations.\"${ANNOTATION_NAME}\""
}

get_annotations_key() {
  echo $ENCRYPTION_ANNOTATION | tr -d ' ' | awk -F':' '{print $1}'
}

get_encryption_hash() {
  echo $ENCRYPTION_ANNOTATION | tr -d ' ' | awk -F':' '{print $2}'
}

apiserver_compare() {
  echo "${apiservers[@]}" | tr ' ' '\n' | sort | uniq > "${TEMP_DIR}/a.txt"
  echo "${updated_apiservers[@]}" | tr ' ' '\n' | sort | uniq > "${TEMP_DIR}/b.txt"
  comm -3 "${TEMP_DIR}/a.txt" "${TEMP_DIR}/b.txt"
}

{{- $envAll := . }}


{{- if and (.Values.conf) (hasKey .Values.conf "encryption_provider") }}

ENCRYPTION_ANNOTATION='{{ $envAll | include "kubernetes_apiserver.key_annotation" }}'
KUBE_SERVICE_NAMESPACE=${KUBE_SERVICE_NAMESPACE:-"kube-system"}
KUBE_SERVICE_NAME=${KUBE_SERVICE_NAME:-"kubernetes-apiserver"}

apiservers=( $(get_service_endpoints "$KUBE_SERVICE_NAMESPACE" "$KUBE_SERVICE_NAME"))
updated_apiservers=()

annotation="$(get_annotations_key)"

# TODO(sh8121att) add timeout logic
while [[ -n "$(apiserver_compare)" ]];
do
  for pod_name in "${apiservers[@]}";
  do
    pod_key=$(get_pod_annotation "$KUBE_SERVICE_NAMESPACE" "$pod_name")
    if [ "$pod_key" == "$(get_encryption_hash)" ];
    then
      updated_apiservers+=("$pod_name")
    fi
  done
done

echo "All apiserver instances have an updated key."

while true
do
  kubectl get secrets --all-namespaces -o json | kubectl replace --validate=false -f -
  if [[ $? -eq 0 ]]
  then
    echo "All secret resources re-encrypted."
    exit 0
  fi
done
{{- end -}}
