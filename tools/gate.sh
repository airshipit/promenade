#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath $(dirname $0))
export WORKSPACE=$(realpath ${SCRIPT_DIR}/..)
export GATE_UTILS=${WORKSPACE}/tools/g2/lib/all.sh
export TEMP_DIR=$(mktemp -d)
chmod -R 755 ${TEMP_DIR}

export GATE_COLOR=${GATE_COLOR:-1}

MANIFEST_ARG=${1:-resiliency}
export GATE_MANIFEST=${WORKSPACE}/tools/g2/manifests/${MANIFEST_ARG}.json

source ${GATE_UTILS}

STAGES_DIR=${WORKSPACE}/tools/g2/stages

log_temp_dir ${TEMP_DIR}
echo

STAGES=$(mktemp)
jq -cr '.stages | .[]' ${GATE_MANIFEST} > ${STAGES}

# NOTE(mark-burnett): It is necessary to use a non-stdin file descriptor for
# the read below, since we will be calling SSH, which will consume the
# remaining data on STDIN.
exec 3< $STAGES
while read -u 3 stage; do
    NAME=$(echo ${stage} | jq -r .name)
    STAGE_CMD=${STAGES_DIR}/$(echo ${stage} | jq -r .script)

    if echo ${stage} | jq -e .arguments > /dev/null; then
        ARGUMENTS=($(echo ${stage} | jq -r '.arguments[]'))
    else
        ARGUMENTS=
    fi

    log_stage_header "${NAME}"
    if $STAGE_CMD ${ARGUMENTS[*]}; then
        log_stage_success
    else
        log_color_reset
        log_stage_error "${NAME}" ${LOG_FILE}
        if echo ${stage} | jq -e .on_error > /dev/null; then
            log_stage_diagnostic_header
            ON_ERROR=${WORKSPACE}/$(echo ${stage} | jq -r .on_error)
            set +e
            $ON_ERROR
        fi
        exit 1
    fi
    log_stage_footer "${NAME}"
    echo
done

echo
log_huge_success
