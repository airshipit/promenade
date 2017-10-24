#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

rsync_cmd ${TEMP_DIR}/scripts/*genesis* ${GENESIS_NAME}:/root/promenade/

ssh_cmd ${GENESIS_NAME} /root/promenade/genesis.sh
ssh_cmd ${GENESIS_NAME} /root/promenade/validate-genesis.sh
