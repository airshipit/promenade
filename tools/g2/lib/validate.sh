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
    sleep 10
    log Validating "${CLUSTER}" etcd membership via "${VM}" for members: "${EXPECTED_MEMBERS[@]}"
    FOUND_MEMBERS=$(etcdctl_member_list "${CLUSTER}" "${VM}" | tr '\n' ' ' | sed 's/ $//')

    if [[ "x${EXPECTED_MEMBERS}" != "x${FOUND_MEMBERS}" ]]; then
        log Etcd membership check failed for cluster "${CLUSTER}"
        log "Found \"${FOUND_MEMBERS}\", expected \"${EXPECTED_MEMBERS}\""
        exit 1
    fi
}
