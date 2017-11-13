#!/usr/bin/env bash

set -e

if [ $# -le 0 ]; then
    echo "Must specify at least one vm to join"
    exit 1
fi

source "${GATE_UTILS}"

JOIN_TARGETS="${*}"

for NAME in ${JOIN_TARGETS}; do
    rsync_cmd "${TEMP_DIR}"/scripts/*"${NAME}"* "${NAME}:/root/promenade/"

    ssh_cmd "${NAME}" "/root/promenade/join-${NAME}.sh"
    ssh_cmd "${NAME}" "/root/promenade/validate-${NAME}.sh"

    # NOTE(mark-burnett): Ensure disk cache is flushed after join.
    ssh_cmd "${NAME}" sync
done

validate_cluster n0

validate_etcd_membership kubernetes n0 genesis "${*}"
validate_etcd_membership calico n0 n0 "${*}"
