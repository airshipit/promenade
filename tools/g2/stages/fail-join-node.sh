#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

while getopts "n:v:" opt; do
    case "${opt}" in
        n)
            NODE="${OPTARG}"
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

SCRIPT_DIR="${TEMP_DIR}/join-fail-curled-scripts"

mkdir -p "${SCRIPT_DIR}"

CURL_ARGS=("-v" "--fail" "--max-time" "300")

promenade_health_check "${VIA}"

LABELS=(
    "foo=bar"
)

USE_DECKHAND=0
JOIN_CURL_URL="$(promenade_render_curl_url "${NODE}" "${USE_DECKHAND}" "" "${LABELS[@]}")"
log "Attempting to get join script (should fail) via: ${JOIN_CURL_URL}"
if ! ssh_cmd "${VIA}" curl "${CURL_ARGS[@]}" \
    "${JOIN_CURL_URL}" > "${SCRIPT_DIR}/join-${NODE}.sh"; then
    log "Failed to get join script"
else
    log "No failure when fetching join script"
    exit 1
fi
