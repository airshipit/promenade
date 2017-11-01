promenade_teardown_node() {
    TARGET=${1}
    VIA=${2}

    ssh_cmd "${TARGET}" /usr/local/bin/promenade-teardown
    kubectl_cmd "${VIA}" delete node "${TARGET}"
}
