validate_cluster() {
    NAME=${1}

    log Validating cluster via VM "${NAME}"
    rsync_cmd "${TEMP_DIR}/scripts/validate-cluster.sh" "${NAME}:/root/promenade/"
    ssh_cmd "${NAME}" /root/promenade/validate-cluster.sh
}

validate_etcd_membership() {
    CLUSTER=${1}
    VM=${2}
    shift 2
    EXPECTED_MEMBERS="${*}"

    # NOTE(mark-burnett): Wait a moment for disks in test environment to settle.
    sleep 60
    log Validating "${CLUSTER}" etcd membership via "${VM}" for members: "${EXPECTED_MEMBERS[@]}"

    local retries=25
    for ((n=0;n<=$retries;n++)); do
        FOUND_MEMBERS=$(etcdctl_member_list "${CLUSTER}" "${VM}" | tr '\n' ' ' | sed 's/ $//')

        log "Found \"${FOUND_MEMBERS}\", expected \"${EXPECTED_MEMBERS}\""
        if [[ "x${EXPECTED_MEMBERS}" != "x${FOUND_MEMBERS}" ]]; then
            log Etcd membership check failed for cluster "${CLUSTER}" on attempt "$n".
            if [[ "$n" == "$retries" ]]; then
                log Etcd membership check failed for cluster "${CLUSTER}" after "$n" retries. Exiting.
                exit 1
            fi
            sleep 30
        else
            log Etcd membership check succeeded for cluster "${CLUSTER}" on attempt "${n}"
            break
        fi
    done
}
