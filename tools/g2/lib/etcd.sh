etcdctl_cmd() {
    CLUSTER=${1}
    VM=${2}

    shift 2

    kubectl_cmd "${VM}" -n kube-system exec -t "${CLUSTER}-etcd-${VM}" -- etcdctl "${@}"
}

etcdctl_member_list() {
    CLUSTER=${1}
    VM=${2}
    shift 2

    etcdctl_cmd "${CLUSTER}" "${VM}" member list -w json | jq -r '.members[].name' | sort
}

etcdctl_member_remove() {
    CLUSTER=${1}
    VM=${2}
    NODE=${3}
    shift 3

    MEMBER_ID=$(etcdctl_cmd $CLUSTER ${VM} member list | awk -F', ' "/${NODE}/ "'{ print $1}')
    if  [[ -n $MEMBER_ID ]] ; then
            etcdctl_cmd "${CLUSTER}" "${VM}" member remove "$MEMBER_ID"
    else
            log  No members found in cluster "$CLUSTER" for node "$NODE"
    fi
}
