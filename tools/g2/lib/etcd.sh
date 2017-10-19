etcdctl_cmd() {
    CLUSTER=${1}
    VM=${2}

    shift 2

    kubectl_cmd ${VM} -n kube-system exec -t ${CLUSTER}-etcd-${VM} -- etcdctl ${@}
}

etcdctl_member_list() {
    CLUSTER=${1}
    VM=${2}
    shift 2
    EXTRA_ARGS=${@}

    etcdctl_cmd ${CLUSTER} ${VM} member list -w json | jq -r '.members[].name' | sort
}
