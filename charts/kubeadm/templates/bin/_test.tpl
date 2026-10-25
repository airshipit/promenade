{{/*
Copyright 2025 AT&T Intellectual Property.  All other rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/ -}}

{{- /* helm test: the sanity check of the cluster, run on a control plane node
     with chroot (see _pod-test.yaml) from the bin ConfigMap */ -}}
{{- $envAll := . -}}
{{- $fullname := include "kubeadm.fullname" $envAll -}}
{{- $version := ($envAll.Values.cluster_config).kubernetesVersion | default "" -}}
{{- $masters := $envAll.Values.anchor.labels.masters -}}
#!/bin/bash

set -uo pipefail

FAILURES=0

check_result() {
  local status="$1"
  shift
  echo "check ${status} $*"
  if [ "${status}" = "FAIL" ]; then
    FAILURES=$((FAILURES + 1))
  fi
}

kubectl() {
  command kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"
}

# the anchors are ready when the reconcile and its node checks passed
check_rollout() {
  local ds="$1"
  if kubectl -n {{ $envAll.Release.Namespace }} rollout status "daemonset/${ds}" --timeout={{ $envAll.Values.checks.helm_test.rollout_timeout }}; then
    check_result OK rollout "${ds}"
  else
    check_result FAIL rollout "${ds}: not rolled out"
  fi
}

check_node_readiness() {
  local not_ready
  not_ready=$(kubectl get nodes \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' |
    awk '$2 != "True" {print $1}')
  if [ -z "${not_ready}" ]; then
    check_result OK nodes "all ready"
  else
    check_result FAIL nodes "not ready:" ${not_ready}
  fi
}

# the static pods of the control plane on every control plane node
check_control_plane() {
  local node component ready
  for node in $(kubectl get nodes -l {{ $masters.node_selector_key }}={{ $masters.node_selector_value }} -o jsonpath='{.items[*].metadata.name}'); do
    for component in kube-apiserver kube-controller-manager kube-scheduler; do
      ready=$(kubectl -n kube-system get pod "${component}-${node}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      if [ "${ready}" = "True" ]; then
        check_result OK control-plane "${component}-${node}"
      else
        check_result FAIL control-plane "${component}-${node}: not ready"
      fi
    done
  done
}

check_versions() {
{{- if $version }}
  local wrong
  # "<node|pod> <version|image>" not of the version
  wrong=$(
    kubectl get nodes \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' |
      awk '$2 != "{{ $version }}"'
    kubectl -n kube-system get pods -l 'component in (kube-apiserver,kube-controller-manager,kube-scheduler)' \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' |
      awk '$2 !~ /:{{ $version }}$/'
  )
  if [ -z "${wrong}" ]; then
    check_result OK versions "kubelets and control plane {{ $version }}"
  else
    check_result FAIL versions "not {{ $version }}:"
    echo "${wrong}"
  fi
{{- else }}
  check_result SKIP versions "cluster_config.kubernetesVersion isn't set"
{{- end }}
}

# a member for every etcd pod: no members left of removed nodes
check_etcd_members() {
  local pods pod members
  pods=$(kubectl -n kube-system get pods -l component=etcd --field-selector status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}') || pods=""
  if [ -z "${pods}" ]; then
    check_result SKIP etcd-members "no running etcd pods"
    return 0
  fi
  pod=$(head -n 1 <<< "${pods}")
  if ! members=$(kubectl -n kube-system exec "${pod}" -- etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
      --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
      member list); then
    check_result FAIL etcd-members "etcdctl member list failed in ${pod}"
    return 0
  fi
  if [ "$(grep -c . <<< "${members}")" -eq "$(grep -c . <<< "${pods}")" ]; then
    check_result OK etcd-members "$(grep -c . <<< "${members}") members"
  else
    check_result FAIL etcd-members "$(grep -c . <<< "${members}") members, $(grep -c . <<< "${pods}") etcd pods:"
    echo "${members}"
  fi
}

{{- if $envAll.Values.manifests.daemonset_masters }}
check_rollout {{ $fullname }}-masters-anchor
{{- end }}
{{- if $envAll.Values.manifests.daemonset_workers }}
check_rollout {{ $fullname }}-workers-anchor
{{- end }}
check_node_readiness
check_control_plane
check_versions
check_etcd_members

if [ "${FAILURES}" -gt 0 ]; then
  echo "helm test: ${FAILURES} checks failed" >&2
  exit 1
fi
echo "helm test passed"
