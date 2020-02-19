#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

VIA="n1"

CURL_ARGS=("-v" "--max-time" "600" "--retry" "20" "--retry-delay" "15" "--connect-timeout" "30" "--progress-bar")

log "Adding labels to node n0"
JSON="{\"calico-etcd\": \"enabled\", \"coredns\": \"enabled\", \"kubernetes-apiserver\": \"enabled\", \"kubernetes-controller-manager\": \"enabled\", \"kubernetes-etcd\": \"enabled\", \"kubernetes-scheduler\": \"enabled\", \"ucp-control-plane\": \"enabled\"}"

ssh_cmd "${VIA}" curl "${CURL_ARGS[@]}" -X PUT -H "Content-Type: application/json" -d "${JSON}" "$(promenade_put_labels_url n0)"

# Need to wait
sleep 120

validate_etcd_membership kubernetes n1 n0 n1 n2 n3
validate_etcd_membership calico n1 n0 n1 n2 n3

log Removing labels from node n2
JSON="{\"coredns\": \"enabled\", \"ucp-control-plane\": \"enabled\"}"

ssh_cmd "${VIA}" curl "${CURL_ARGS[@]}" -X PUT -H "Content-Type: application/json" -d "${JSON}" "$(promenade_put_labels_url n2)"

# Need to wait
sleep 120

validate_cluster n1

validate_etcd_membership kubernetes n1 n0 n1 n3
validate_etcd_membership calico n1 n0 n1 n3
