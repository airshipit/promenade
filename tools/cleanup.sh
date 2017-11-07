#!/bin/bash

set -eux

log ()  {
    printf "$(date)\t%s\n" "${1}"
}


TO_RM=(
    "/etc/cni"
    "/etc/coredns"
    "/etc/etcd"
    "/etc/genesis"
    "/etc/kubernetes"
    "/etc/systemd/system/kubelet.service"
    "/home/ceph"
    "/var/lib/etcd"
    "/var/lib/kubelet/pods"
    "/var/lib/openstack-helm"
    "/var/log/containers"
    "/var/log/pods"
)


prune_docker() {
    log "Docker prune"
    docker volume prune -f
    docker system prune -a -f
}

remove_containers() {
    log "Remove all Docker containers"
    docker ps -aq 2> /dev/null | xargs --no-run-if-empty docker rm -fv
}

remove_files() {
    for item in "${TO_RM[@]}"; do
        log "Removing ${item}"
        rm -rf "${item}"
    done
}

reset_docker() {
    log "Remove all local Docker images"
    docker images -qa | xargs --no-run-if-empty docker rmi -f

    log "Remove remaining Docker files"
    systemctl stop docker
    if ! rm -rf /var/lib/docker/*; then
        log "Failed to cleanup some files in /var/lib/docker"
        find /var/lib/docker
    fi
    systemctl start docker
}

stop_kubelet() {
    log "Stop Kubelet and clean pods"
    systemctl stop kubelet || true

    # Issue with orhan PODS
    # https://github.com/kubernetes/kubernetes/issues/38498
    find /var/lib/kubelet/pods 2> /dev/null | while read orphan_pod; do
        if [[ ${orphan_pod} == *io~secret/* ]] || [[ ${orphan_pod} == *empty-dir/* ]]; then
            umount "${orphan_pod}" || true
            rm -rf "${orphan_pod}"
        fi
    done
}


FORCE=0
RESET_DOCKER=0

while getopts "fk" opt; do
    case "${opt}" in
        f)
            FORCE=1
            ;;
        k)
            RESET_DOCKER=1
            ;;
        *)
            echo "Unknown option"
            exit 1
            ;;
    esac
done

if [[ $FORCE == "0" ]]; then
    echo Warning:  This cleanup script is very aggresive.  Run with -f to avoid this prompt.
    while true; do
        read -p "Are you sure you wish to proceed with aggressive cleanup?" yn
        case $yn in
            [Yy]*)
                RESET_DOCKER=1
                break
                ;;
            *)
                echo Exitting.
                exit 1
        esac
    done
fi

stop_kubelet
remove_containers
remove_files
prune_docker

systemctl daemon-reload

if [[ $RESET_DOCKER == "1" ]]; then
    reset_docker
fi
