#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a NODES

RECREATE=0

while getopts "e:n:rv:" opt; do
    case "${opt}" in
        e)
            ETCD_CLUSTERS+=("${OPTARG}")
            ;;
        n)
            NODES+=("${OPTARG}")
            ;;
        r)
            RECREATE=1
            ;;
        v)
            VIA=${OPTARG}
            ;;
        *)
            echo "Unknown option"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -gt 0 ]; then
    echo "Unknown arguments specified: ${*}"
    exit 1
fi

for NAME in "${NODES[@]}"; do
    log Tearing down node "${NAME}"
    promenade_teardown_node "${NAME}" "${VIA}"
    for ETCD_CLUSTER in "${ETCD_CLUSTERS[@]}"; do
        etcdctl_member_remove "${ETCD_CLUSTER}" "${VIA}" "${NAME}"
    done
    vm_clean "${NAME}"
    if [[ ${RECREATE} == "1" ]]; then
        vm_create "${NAME}"
    fi
done
