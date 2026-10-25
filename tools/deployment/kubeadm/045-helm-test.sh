#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The helm test of the kubeadm chart: the chart is deployed with kubectl, so
# the test pod rendered by 035-generate-catalog.sh is run the way helm test
# runs it. It waits for the anchors (their readiness includes the node checks
# of the chart) and checks the cluster through the API.

set -exo pipefail

: "${WORK_DIR:="${HOME}/kubeadm-gate"}"
: "${NAMESPACE:="kube-system"}"
: "${HELM_TEST_TIMEOUT:="2400"}"

TESTS="${WORK_DIR}/helm-test.yaml"
test -s "${TESTS}"

# helm.sh/hook-delete-policy: before-hook-creation
kubectl -n "${NAMESPACE}" delete -f "${TESTS}" --ignore-not-found --wait
kubectl -n "${NAMESPACE}" create -f "${TESTS}"
PODS=$(kubectl -n "${NAMESPACE}" get -f "${TESTS}" -o name)

rc=0
END=$(($(date +%s) + HELM_TEST_TIMEOUT))
for pod in ${PODS}; do
  until phase=$(kubectl -n "${NAMESPACE}" get "${pod}" -o jsonpath='{.status.phase}') &&
        [[ "${phase}" == "Succeeded" || "${phase}" == "Failed" ]]; do
    if [[ "$(date +%s)" -gt "${END}" ]]; then
      echo "Timed out waiting for ${pod}" >&2
      phase=Timeout
      break
    fi
    sleep 15
  done
  kubectl -n "${NAMESPACE}" logs "${pod}" || true
  if [[ "${phase}" != "Succeeded" ]]; then
    echo "${pod}: ${phase}" >&2
    rc=1
  fi
done
exit "${rc}"
