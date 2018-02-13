#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

rsync_cmd "${TEMP_DIR}/scripts"/*genesis* "${GENESIS_NAME}:/root/promenade/"

set -o pipefail
ssh_cmd "${GENESIS_NAME}" /root/promenade/genesis.sh 2>&1 | tee -a "${LOG_FILE}"
ssh_cmd "${GENESIS_NAME}" /root/promenade/validate-genesis.sh 2>&1 | tee -a "${LOG_FILE}"
set +o pipefail

if ! ssh_cmd n0 docker images | tail -n +2 | grep -v registry:5000 ; then
    log_warn "Using some non-cached docker images.  This will slow testing."
    ssh_cmd n0 docker images | tail -n +2 | grep -v registry:5000 | tee -a "${LOG_FILE}"
fi
