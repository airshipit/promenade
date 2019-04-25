promenade_teardown_node() {
    TARGET=${1}
    VIA=${2}

    ssh_cmd "${TARGET}" /usr/local/bin/promenade-teardown
    kubectl_cmd "${VIA}" delete node "${TARGET}"
}

promenade_render_curl_url() {
    NAME=${1}
    USE_DECKHAND=${2}
    DECKHAND_REVISION=${3}
    shift 3
    LABELS=(${@})

    LABEL_PARAMS=
    for label in "${LABELS[@]}"; do
        LABEL_PARAMS+="&labels.dynamic=${label}"
    done

    BASE_URL="${PROMENADE_BASE_URL}/api/v1.0/join-scripts"
    if [[ ${USE_DECKHAND} == 1 ]]; then
        DESIGN_REF="design_ref=deckhand%2Bhttp://deckhand-int.ucp.svc.cluster.local:9000/api/v1.0/revisions/${DECKHAND_REVISION}/rendered-documents"
    else
        DESIGN_REF="design_ref=${NGINX_URL}/promenade.yaml"
    fi
    HOST_PARAMS="hostname=${NAME}&ip=$(config_vm_ip "${NAME}")&external_ip=$(config_vm_ip "${NAME}")"

    echo "${BASE_URL}?${DESIGN_REF}&${HOST_PARAMS}&leave_kubectl=true${LABEL_PARAMS}"
}

promenade_render_validate_url() {
    echo "${PROMENADE_BASE_URL}/api/v1.0/validatedesign"
}

promenade_render_validate_body() {
    USE_DECKHAND=${1}
    DECKHAND_REVISION=${2}

    if [[ ${USE_DECKHAND} == 1 ]]; then
        JSON="{\"rel\":\"design\",\"href\":\"deckhand+http://deckhand-int.ucp.svc.cluster.local:9000/api/v1.0/revisions/${DECKHAND_REVISION}/rendered-documents\",\"type\":\"application/x-yaml\"}"
    else
        JSON="{\"rel\":\"design\",\"href\":\"${NGINX_URL}/promenade.yaml\",\"type\":\"application/x-yaml\"}"
    fi

    echo "${JSON}"
}

promenade_health_check() {
    VIA=${1}
    log "Checking Promenade API health"
    MAX_HEALTH_ATTEMPTS=6
    for attempt in $(seq ${MAX_HEALTH_ATTEMPTS}); do
        if ssh_cmd "${VIA}" curl -v --fail "${PROMENADE_BASE_URL}/api/v1.0/health"; then
            log "Promenade API healthy"
            break
        elif [[ $attempt == "${MAX_HEALTH_ATTEMPTS}" ]]; then
            log "Promenade health check failed, max retries (${MAX_HEALTH_ATTEMPTS}) exceeded."
            exit 1
        fi
        sleep 10
    done
}

promenade_put_labels_url() {
    NODE_NAME=${1}
    echo "${PROMENADE_BASE_URL}/api/v1.0/node-labels/${NODE_NAME}"
}
