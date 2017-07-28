#!/usr/bin/env bash

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

set -ex

export KUBECONFIG=/etc/kubernetes/admin/kubeconfig.yaml

function log {
    echo $* 1>&2
}

function report_docker_exited_containers {
    for container_id in $(docker ps -q --filter "status=exited"); do
        log Report for exited container $container_id
        docker inspect $container_id
        docker logs $container_id
    done
}

function report_docker_state {
    log General docker state report
    docker info
    docker ps -a
    report_docker_exited_containers
}

function report_kube_state {
    log General cluster state report
    kubectl get nodes 1>&2
    kubectl get --all-namespaces pods -o wide 1>&2
}

function fail {
    report_docker_state
    report_kube_state
    exit 1
}

function wait_for_ready_nodes {
    set +x

    NODES=$1
    SECONDS=${2:-600}

    log $(date) Waiting $SECONDS seconds for $NODES Ready nodes.

    NODE_READY_JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[?(@.type=="Ready")]}{@.type}={@.status}{"\n"}{end}{end}'

    end=$(($(date +%s) + $SECONDS))
    while true; do
        READY_NODE_COUNT=$(kubectl get nodes -o jsonpath="${NODE_READY_JSONPATH}" | grep "Ready=True" | wc -l)
        if [ $NODES -ne $READY_NODE_COUNT ]; then
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log $(date) Nodes were not all ready before timeout.
                fail
            fi
            sleep 5
        else
            log $(date) Found expected nodes.
            break
        fi
    done

    set -x
}

function wait_for_pod_termination {
    set +x

    NAMESPACE=$1
    POD_NAME=$2
    SECONDS=${3:-120}

    log $(date) Waiting $SECONDS seconds for termination of pod $POD_NAME

    POD_PHASE_JSONPATH='{.status.phase}'

    end=$(($(date +%s) + $SECONDS))
    while true; do
        POD_PHASE=$(kubectl --namespace $NAMESPACE get -o jsonpath="${POD_PHASE_JSONPATH}" pod $POD_NAME)
        if [ "x$POD_PHASE" = "xSucceeded" ]; then
            log $(date) Pod $POD_NAME succeeded.
            break
        elif [ "x$POD_PHASE" = "xFailed" ]; then
            log $(date) Pod $POD_NAME failed.
            kubectl --namespace $NAMESPACE get -o yaml pod $POD_NAME 1>&2
            fail
        else
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log $(date) Pod did not terminate before timeout.
                kubectl --namespace $NAMESPACE get -o yaml pod $POD_NAME 1>&2
                fail
            fi
            sleep 1
        fi
    done

    set -x
}

function validate_kubectl_logs {
    NAMESPACE=default
    POD_NAME=log-test-$(date +%s)

    cat <<EOPOD | kubectl --namespace $NAMESPACE apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  restartPolicy: Never
  containers:
  - name: noisy
    image: busybox
    imagePullPolicy: IfNotPresent
    command:
    - /bin/echo
    - EXPECTED RESULT
...
EOPOD

    wait_for_pod_termination $NAMESPACE $POD_NAME
    ACTUAL_LOGS=$(kubectl logs $POD_NAME)
    if [ "x$ACTUAL_LOGS" != "xEXPECTED RESULT" ]; then
        log Got unexpected logs:
        kubectl --namespace $NAMESPACE logs $POD_NAME 1>&2
        fail
    fi
}
