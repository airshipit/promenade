#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a ETCD_CLUSTERS
declare -a LABELS
declare -a NODES

GET_KEYSTONE_TOKEN=0
USE_DECKHAND=0

while getopts "d:e:l:n:tv:" opt; do
    case "${opt}" in
        e)
            ETCD_CLUSTERS+=("${OPTARG}")
            ;;
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
BASE_PROM_URL="http://promenade-api.ucp.svc.cluster.local"

echo Etcd Clusters: "${ETCD_CLUSTERS[@]}"
echo Labels: "${LABELS[@]}"
echo Nodes: "${NODES[@]}"

render_curl_url() {
    NAME=${1}
    shift
    LABELS=(${@})

    LABEL_PARAMS=
    for label in "${LABELS[@]}"; do
        LABEL_PARAMS+="&labels.dynamic=${label}"
    done

    BASE_URL="${BASE_PROM_URL}/api/v1.0/join-scripts"
    if [[ ${USE_DECKHAND} == 1 ]]; then
        DESIGN_REF="design_ref=deckhand%2Bhttp://deckhand-int.ucp.svc.cluster.local:9000/api/v1.0/revisions/${DECKHAND_REVISION}/rendered-documents"
    else
        DESIGN_REF="design_ref=${NGINX_URL}/promenade.yaml"
    fi
    HOST_PARAMS="hostname=${NAME}&ip=$(config_vm_ip "${NAME}")"

    echo "${BASE_URL}?${DESIGN_REF}&${HOST_PARAMS}${LABEL_PARAMS}"
}

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
        log "Got keystone token: ${TOKEN}"
        CURL_ARGS+=("-H" "X-Auth-Token: ${TOKEN}")
    fi

    log "Checking Promenade API health"
    MAX_HEALTH_ATTEMPTS=6
    for attempt in $(seq ${MAX_HEALTH_ATTEMPTS}); do
        if ssh_cmd "${VIA}" curl -v "${CURL_ARGS[@]}" "${BASE_PROM_URL}/api/v1.0/health"; then
            log "Promenade API healthy"
            break
        elif [[ $attempt == "${MAX_HEALTH_ATTEMPTS}" ]]; then
            log "Promenade health check failed, max retries (${MAX_HEALTH_ATTEMPTS}) exceeded."
            exit 1
        fi
        sleep 10
    done

    JOIN_CURL_URL="$(render_curl_url "${NAME}" "${LABELS[@]}")"
    log "Fetching join script via: ${JOIN_CURL_URL}"
    ssh_cmd "${VIA}" curl "${CURL_ARGS[@]}" \
        "${JOIN_CURL_URL}" > "${SCRIPT_DIR}/join-${NAME}.sh"

    chmod 755 "${SCRIPT_DIR}/join-${NAME}.sh"
    log "Join script received"

    log Joining node "${NAME}"
    rsync_cmd "${SCRIPT_DIR}/join-${NAME}.sh" "${NAME}:/root/promenade/"
    ssh_cmd "${NAME}" "/root/promenade/join-${NAME}.sh" 2>&1 | tee -a "${LOG_FILE}"
done

for etcd_validation_string in "${ETCD_CLUSTERS[@]}"; do
    IFS=' ' read -a etcd_validation_args <<<"${etcd_validation_string}"
    validate_etcd_membership "${etcd_validation_args[@]}"
done
