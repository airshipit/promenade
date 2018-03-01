#!/usr/bin/env bash

# NOTE(mark-burnett): Keep trying to collect info even if there's an error
set +e
set -x

source "${GATE_UTILS}"

ERROR_DIR="${TEMP_DIR}/errors"
VIA=n0
mkdir -p "${ERROR_DIR}"

log "Gathering info from failed genesis server (n0) in ${ERROR_DIR}"

log "Gathering docker info for exitted containers"
mkdir -p "${ERROR_DIR}/docker"
docker_ps "${VIA}" | tee "${ERROR_DIR}/docker/ps"
docker_info "${VIA}" | tee "${ERROR_DIR}/docker/info"

for container_id in $(docker_exited_containers "${VIA}"); do
    docker_inspect "${VIA}" "${container_id}" | tee "${ERROR_DIR}/docker/${container_id}"
    echo "=== Begin logs ===" | tee -a "${ERROR_DIR}/docker/${container_id}"
    docker_logs "${VIA}" "${container_id}" | tee -a "${ERROR_DIR}/docker/${container_id}"
done

log "Gathering kubectl output"
mkdir -p "${ERROR_DIR}/kube"
kubectl_cmd "${VIA}" describe nodes n0 | tee "${ERROR_DIR}/kube/n0"
kubectl_cmd "${VIA}" get --all-namespaces -o wide pod | tee "${ERROR_DIR}/kube/pods"
