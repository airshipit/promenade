#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath $(dirname $0))
export WORKSPACE=$(realpath ${SCRIPT_DIR}/..)
export GATE_UTILS=${WORKSPACE}/tools/g2/lib/all.sh

source ${GATE_UTILS}

vm_clean_all
registry_down
