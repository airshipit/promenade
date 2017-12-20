#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

while getopts "v:" opt; do
    case "${opt}" in
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

TOKEN=$(os_ks_get_token "${VIA}")

DECKHAND_URL=http://deckhand-int.ucp.svc.cluster.local:9000/api/v1.0/buckets/prom/documents

rsync_cmd "${TEMP_DIR}/nginx/promenade.yaml" "${VIA}:/root/promenade/promenade.yaml"
ssh_cmd "${VIA}" curl -v \
    --fail \
    --max-time 300 \
    --retry 10 \
    --retry-delay 15 \
    -H "X-Auth-Token: ${TOKEN}" \
    -H "Content-Type: application/x-yaml" \
    -T "/root/promenade/promenade.yaml" \
    "${DECKHAND_URL}"
