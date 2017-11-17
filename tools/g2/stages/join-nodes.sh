#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

declare -a ETCD_CLUSTERS
declare -a LABELS
declare -a NODES

while getopts "e:l:n:v:" opt; do
    case "${opt}" in
        e)
            ETCD_CLUSTERS+=("${OPTARG}")
            ;;
        l)
            LABELS+=("${OPTARG}")
            ;;
        n)
            NODES+=("${OPTARG}")
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

    BASE_URL="http://promenade-api.ucp.svc.cluster.local/api/v1.0/join-scripts"
    DESIGN_REF="design_ref=http://192.168.77.1:7777/promenade.yaml"
    HOST_PARAMS="hostname=${NAME}&ip=$(config_vm_ip "${NAME}")"

    echo "'${BASE_URL}?${DESIGN_REF}&${HOST_PARAMS}${LABEL_PARAMS}'"
}

mkdir -p "${SCRIPT_DIR}"

for NAME in "${NODES[@]}"; do
    log Building join script for node "${NAME}"

    ssh_cmd "${VIA}" curl "$(render_curl_url "${NAME}" "${LABELS[@]}")" > "${SCRIPT_DIR}/join-${NAME}.sh"
    chmod 755 "${SCRIPT_DIR}/join-${NAME}.sh"

    log Joining node "${NAME}"
    rsync_cmd "${SCRIPT_DIR}/join-${NAME}.sh" "${NAME}:/root/promenade/"
    ssh_cmd "${NAME}" "/root/promenade/join-${NAME}.sh"
done

for etcd_validation_string in "${ETCD_CLUSTERS[@]}"; do
    IFS=' ' read -a etcd_validation_args <<<"${etcd_validation_string}"
    validate_etcd_membership "${etcd_validation_args[@]}"
done
