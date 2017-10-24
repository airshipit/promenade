#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

log Adding labels to node n0
kubectl_cmd n1 label node n0 \
    calico-etcd=enabled \
    kubernetes-apiserver=enabled \
    kubernetes-controller-manager=enabled \
    kubernetes-etcd=enabled \
    kubernetes-scheduler=enabled

# XXX Need to wait
sleep 60

validate_etcd_membership kubernetes n1 n0 n1 n2 n3
validate_etcd_membership calico n1 n0 n1 n2 n3

log Removing labels from node n2
kubectl_cmd n1 label node n2 \
    calico-etcd- \
    kubernetes-apiserver- \
    kubernetes-controller-manager- \
    kubernetes-etcd- \
    kubernetes-scheduler-

# XXX Need to wait
sleep 60

validate_cluster n1

validate_etcd_membership kubernetes n1 n0 n1 n3
validate_etcd_membership calico n1 n0 n1 n3
