#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a NODES
SYNC_BEFORE_STOP=0

while getopts "n:s" opt; do
    case "${opt}" in
        n)
            NODES+=("${OPTARG}")
            ;;
        s)
            SYNC_BEFORE_STOP=1
            ;;
        *)
            echo "Unknown option"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

for node in "${NODES[@]}"; do
    if [[ $SYNC_BEFORE_STOP == 1 ]]; then
        ssh_cmd "${node}" sync
    fi
    vm_stop "${node}"
done
