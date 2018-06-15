#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a LABELS
declare -a NODES

GET_KEYSTONE_TOKEN=0
USE_DECKHAND=0
DECKHAND_REVISION=''

while getopts "d:l:n:tv:" opt; do
    case "${opt}" in
        d)
            USE_DECKHAND=1
            DECKHAND_REVISION=${OPTARG}
            ;;
        l)
            LABELS+=("${OPTARG}")
            ;;
        n)
            NODES+=("${OPTARG}")
            ;;
        t)
            GET_KEYSTONE_TOKEN=1
            ;;
        v)
            VIA=${OPTARG}
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

SCRIPT_DIR="${TEMP_DIR}/curled-scripts"

echo Labels: "${LABELS[@]}"
echo Nodes: "${NODES[@]}"

mkdir -p "${SCRIPT_DIR}"

for NAME in "${NODES[@]}"; do
    log Building join script for node "${NAME}"

    CURL_ARGS=("--fail" "--max-time" "300" "--retry" "16" "--retry-delay" "15")
    if [[ $GET_KEYSTONE_TOKEN == 1 ]]; then
        TOKEN="$(os_ks_get_token "${VIA}")"
        if [[ -z $TOKEN ]]; then
            log Failed to get keystone token, exiting.
            exit 1
        fi
        TOKEN_HASH=$(echo -n "${TOKEN}" | md5sum)
        log "Got keystone token, token md5sum: ${TOKEN_HASH}"
        CURL_ARGS+=("-H" "X-Auth-Token: ${TOKEN}")
    fi

    promenade_health_check "${VIA}"

    log "Validating documents"
    ssh_cmd "${VIA}" curl -v "${CURL_ARGS[@]}" -X POST -H "Content-Type: application/json" -d "$(promenade_render_validate_body "${USE_DECKHAND}" "${DECKHAND_REVISION}")" "$(promenade_render_validate_url)"

    JOIN_CURL_URL="$(promenade_render_curl_url "${NAME}" "${USE_DECKHAND}" "${DECKHAND_REVISION}" "${LABELS[@]}")"
    log "Fetching join script via: ${JOIN_CURL_URL}"
    ssh_cmd "${VIA}" curl "${CURL_ARGS[@]}" \
        "${JOIN_CURL_URL}" > "${SCRIPT_DIR}/join-${NAME}.sh"

    chmod 755 "${SCRIPT_DIR}/join-${NAME}.sh"
    log "Join script received"

    log Joining node "${NAME}"
    rsync_cmd "${SCRIPT_DIR}/join-${NAME}.sh" "${NAME}:/root/promenade/"
    ssh_cmd "${NAME}" "/root/promenade/join-${NAME}.sh" 2>&1 | tee -a "${LOG_FILE}"
done
