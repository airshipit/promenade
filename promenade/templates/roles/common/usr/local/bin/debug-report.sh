#!/usr/bin/env bash

set -ux

SUBDIR_NAME=debug-$(hostname)
BASETEMP=${BASETEMP:-"/var/tmp"}
NAMESPACE_PATTERN=${NAMESPACE_PATTERN:-'.*'}
# NOTE: Duration of newer pods logs that need to be fetched. Defaults to all logs.
# Passing value 0s will fetch all logs.
LOG_DURATION=${LOG_DURATION:-"0s"}
export LOG_DURATION

# NOTE(mark-burnett): This should add calicoctl to the path.
export PATH=${PATH}:/opt/cni/bin
export KUBECONFIG=${KUBECONFIG:-"/etc/kubernetes/admin/kubeconfig.yaml"}

TEMP_DIR=$(mktemp -d -p "$BASETEMP")
export TEMP_DIR
export BASE_DIR="${TEMP_DIR}/${SUBDIR_NAME}"
export HELM_DIR="${BASE_DIR}/helm"
export CALICO_DIR="${BASE_DIR}/calico"

mkdir -p "${BASE_DIR}"

PARALLELISM_FACTOR=2

function get_namespaces () {
    kubectl get namespaces -o name | awk -F '/' '{ print $NF }' | grep -E "$NAMESPACE_PATTERN"
}

function get_pods () {
    NAMESPACE=$1
    kubectl get pods -n "${NAMESPACE}" -o name | awk -F '/' '{ print $NF }' | xargs -L1 -P 1 -I {} echo "${NAMESPACE}" {}
}
export -f get_pods

function get_pod_logs () {
    NAMESPACE=${1% *}
    POD=${1#* }
    INIT_CONTAINERS=$(kubectl get pod "${POD}" -n "${NAMESPACE}" -o json | jq -r '.spec.initContainers[]?.name')
    CONTAINERS=$(kubectl get pod "${POD}" -n "${NAMESPACE}" -o json | jq -r '.spec.containers[].name')
    POD_DIR="${BASE_DIR}/pod-logs/${NAMESPACE}/${POD}"
    SINCE="${LOG_DURATION}"
    mkdir -p "${POD_DIR}"
    for CONTAINER in ${INIT_CONTAINERS} ${CONTAINERS}; do
        kubectl logs "${POD}" -n "${NAMESPACE}" -c "${CONTAINER}" --since="${SINCE}"  > "${POD_DIR}/${CONTAINER}.txt"
    done
}
export -f get_pod_logs

function list_namespaced_objects () {
    export NAMESPACE=$1
    cat | awk "{ print \"${NAMESPACE} \" \$1 }" <<OBJECTS
configmaps
cronjobs
daemonsets
deployment
endpoints
ingresses
jobs
networkpolicies
pods
persistentvolumeclaims
rolebindings
roles
serviceaccounts
services
statefulsets
OBJECTS
}
export -f list_namespaced_objects

function name_objects () {
    input=($1)
    export NAMESPACE=${input[0]}
    export OBJECT=${input[1]}
    kubectl get -n "${NAMESPACE}" "${OBJECT}" -o name | awk "{ print \"${NAMESPACE} ${OBJECT} \" \$1 }"
}
export -f name_objects

function get_objects () {
    input=($1)
    export NAMESPACE=${input[0]}
    export OBJECT=${input[1]}
    export NAME=${input[2]#*/}
    echo "${NAMESPACE}/${OBJECT}/${NAME}"
    DIR="${BASE_DIR}/objects/namespaced/${NAMESPACE}/${OBJECT}"
    mkdir -p "${DIR}"
    kubectl get -n "${NAMESPACE}" "${OBJECT}" "${NAME}" -o yaml > "${DIR}/${NAME}.yaml"
}
export -f get_objects

function get_releases () {
    helm list --all-namespaces --all | awk 'NR>1 { print $1, $2 }'
}

function get_release () {
    input=($1)
    RELEASE=${input[0]}
    NAMESPACE=${input[1]}
    NAMESPACE_DIR="${HELM_DIR}/${NAMESPACE}"
    mkdir -p "${NAMESPACE_DIR}"
    helm status -n "${NAMESPACE}" "${RELEASE}" > "${NAMESPACE_DIR}/${RELEASE}.txt"
}
export -f get_release

if which helm; then
    mkdir -p "${HELM_DIR}"
    helm list --all-namespaces --all > "${HELM_DIR}/list" &
    get_releases | \
        xargs -r -n 1 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'get_release "$@"' _ {}
fi

kubectl get --all-namespaces -o wide pods > "${BASE_DIR}/pods.txt" &

get_namespaces | \
    xargs -r -n 1 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'get_pods "$@"' _ {} | \
    xargs -r -n 2 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'get_pod_logs "$@"' _ {} &

get_namespaces | \
    xargs -r -n 1 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'list_namespaced_objects "$@"' _ {} | \
    xargs -r -n 1 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'name_objects "$@"' _ {} | \
    xargs -r -n 1 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'get_objects "$@"' _ {} &

iptables-save > "${BASE_DIR}/iptables" &

if which calicoctl; then
    mkdir -p "${CALICO_DIR}"
    for kind in bgpPeer hostEndpoint ipPool nodes policy profile workloadEndpoint; do
        calicoctl get "${kind}" -o yaml > "${CALICO_DIR}/${kind}.yaml" &
    done
fi

wait

if tar zcf "${SUBDIR_NAME}.tgz" -C "${TEMP_DIR}" "${SUBDIR_NAME}"; then
  find "${BASETEMP}" -type d -name "${SUBDIR_NAME}" -prune -exec sh -c 'rm -rf $(dirname "$1")' _ {} \;
fi
echo "Report collected in $TEMP_DIR/${SUBDIR_NAME}.tgz"
