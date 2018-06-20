#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a NODES

while getopts "n:s" opt; do
    case "${opt}" in
        n)
            NODES+=("${OPTARG}")
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
