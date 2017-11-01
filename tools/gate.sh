#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath "$(dirname "${0}")")
WORKSPACE=$(realpath "${SCRIPT_DIR}/..")
GATE_UTILS=${WORKSPACE}/tools/g2/lib/all.sh
TEMP_DIR=${TEMP_DIR:-$(mktemp -d)}
chmod -R 755 "${TEMP_DIR}"

GATE_COLOR=${GATE_COLOR:-1}

MANIFEST_ARG=${1:-resiliency}
GATE_MANIFEST=${WORKSPACE}/tools/g2/manifests/${MANIFEST_ARG}.json

export GATE_COLOR
export GATE_MANIFEST
export GATE_UTILS
export TEMP_DIR
export WORKSPACE

source "${GATE_UTILS}"

STAGES_DIR=${WORKSPACE}/tools/g2/stages

log_temp_dir "${TEMP_DIR}"
echo

STAGES=$(mktemp)
jq -cr '.stages | .[]' "${GATE_MANIFEST}" > "${STAGES}"

# NOTE(mark-burnett): It is necessary to use a non-stdin file descriptor for
# the read below, since we will be calling SSH, which will consume the
# remaining data on STDIN.
exec 3< "$STAGES"
while read -u 3 stage; do
    NAME=$(echo "${stage}" | jq -r .name)
    STAGE_CMD=${STAGES_DIR}/$(echo "${stage}" | jq -r .script)

    log_stage_header "${NAME}"
    if echo "${stage}" | jq -r '.arguments | @sh' | xargs "${STAGE_CMD}" ; then
        log_stage_success
    else
        log_color_reset
        log_stage_error "${NAME}" "${LOG_FILE}"
        if echo "${stage}" | jq -e .on_error > /dev/null; then
            log_stage_diagnostic_header
            ON_ERROR=${WORKSPACE}/$(echo "${stage}" | jq -r .on_error)
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
