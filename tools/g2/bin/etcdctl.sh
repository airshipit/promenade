#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath $(dirname $0))
WORKSPACE=$(realpath ${SCRIPT_DIR}/../../..)
GATE_UTILS=${WORKSPACE}/tools/g2/lib/all.sh

source ${GATE_UTILS}

etcdctl_cmd ${@}
