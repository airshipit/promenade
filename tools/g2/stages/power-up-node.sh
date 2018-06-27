#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a NODES

WAIT=60

while getopts "n:v:w:s" opt; do
    case "${opt}" in
        n)
            NODES+=("${OPTARG}")
            ;;
        v)
            VIA="${OPTARG}"
            ;;
        w)
            WAIT="${OPTARG}"
            ;;
        *)
            echo "Unknown option"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

for node in "${NODES[@]}"; do
    vm_start "${node}"
done

for node in "${NODES[@]}"; do
    kubectl_wait_for_node_ready "${VIA}" "${node}" "${WAIT}"
done
