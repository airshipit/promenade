#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a ETCD_CLUSTERS
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
    vm_clean "${NAME}"
    if [[ ${RECREATE} == "1" ]]; then
        vm_create "${NAME}"
    fi
done

for etcd_validation_string in "${ETCD_CLUSTERS[@]}"; do
    IFS=' ' read -a etcd_validation_args <<<"${etcd_validation_string}"
    validate_etcd_membership "${etcd_validation_args[@]}"
done
