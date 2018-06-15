#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a ETCD_CLUSTERS

WAIT_BEFORE_CHECK=0

while getopts "e:w:" opt; do
    case "${opt}" in
        e)
            ETCD_CLUSTERS+=("${OPTARG}")
            ;;
        w)
            WAIT_BEFORE_CHECK="${OPTARG}"
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

log Waiting "${WAIT_BEFORE_CHECK}" seconds before checking cluster health.
sleep "${WAIT_BEFORE_CHECK}"

for etcd_validation_string in "${ETCD_CLUSTERS[@]}"; do
    IFS=' ' read -a etcd_validation_args <<<"${etcd_validation_string}"
    validate_etcd_membership "${etcd_validation_args[@]}"
done
