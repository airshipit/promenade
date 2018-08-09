#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

VIA="n1"

CURL_ARGS=("--fail" "--max-time" "300" "--retry" "16" "--retry-delay" "15")

log Adding labels to node n0
JSON="{\"calico-etcd\": \"enabled\", \"coredns\": \"enabled\", \"kubernetes-apiserver\": \"enabled\", \"kubernetes-controller-manager\": \"enabled\", \"kubernetes-etcd\": \"enabled\", \"kubernetes-scheduler\": \"enabled\", \"ucp-control-plane\": \"enabled\"}"

ssh_cmd "${VIA}" curl -v "${CURL_ARGS[@]}" -X PUT -H "Content-Type: application/json" -d "${JSON}" "$(promenade_put_labels_url n0)"

# Need to wait
sleep 60

validate_etcd_membership kubernetes n1 n0 n1 n2 n3
validate_etcd_membership calico n1 n0 n1 n2 n3

log Removing labels from node n2
JSON="{\"coredns\": \"enabled\", \"ucp-control-plane\": \"enabled\"}"

ssh_cmd "${VIA}" curl -v "${CURL_ARGS[@]}" -X PUT -H "Content-Type: application/json" -d "${JSON}" "$(promenade_put_labels_url n2)"

# Need to wait
sleep 60

validate_cluster n1

validate_etcd_membership kubernetes n1 n0 n1 n3
validate_etcd_membership calico n1 n0 n1 n3
