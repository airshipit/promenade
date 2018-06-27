kubectl_apply() {
    VIA=${1}
    FILE=${2}
    ssh_cmd "${VIA}" "cat ${FILE} | kubectl apply -f -"
}

kubectl_cmd() {
    VIA=${1}

    shift

    ssh_cmd "${VIA}" kubectl "${@}"
}

kubectl_wait_for_pod() {
    VIA=${1}
    NAMESPACE=${2}
    POD_NAME=${3}
    SEC=${4:-600}
    log Waiting "${SEC}" seconds for termination of pod "${POD_NAME}"

    POD_PHASE_JSONPATH='{.status.phase}'

    end=$(($(date +%s) + SEC))
    while true; do
        POD_PHASE=$(kubectl_cmd "${VIA}" --request-timeout 10s --namespace "${NAMESPACE}" get -o jsonpath="${POD_PHASE_JSONPATH}" pod "${POD_NAME}")
        if [[ ${POD_PHASE} = "Succeeded" ]]; then
            log Pod "${POD_NAME}" succeeded.
            break
        elif [[ $POD_PHASE = "Failed" ]]; then
            log Pod "${POD_NAME}" failed.
            kubectl_cmd "${VIA}" --request-timeout 10s --namespace "${NAMESPACE}" get -o yaml pod "${POD_NAME}" 1>&2
            exit 1
        else
            now=$(date +%s)
            if [[ $now -gt $end ]]; then
                log Pod did not terminate before timeout.
                kubectl_cmd "${VIA}" --request-timeout 10s --namespace "${NAMESPACE}" get -o yaml pod "${POD_NAME}" 1>&2
                exit 1
            fi
            sleep 1
        fi
    done
}

kubectl_wait_for_node_ready() {
    set +x

    VIA=${1}
    NODE_NAME=${2}
    SEC=${3:-300}

    log Waiting $SEC seconds for $NODE_NAME to be ready.

    NODE_READY_JSONPATH='{.status.conditions[?(@.type=="Ready")].status}'

    end=$(($(date +%s) + $SEC))
    while true; do
        if (kubectl_cmd "${VIA}" --request-timeout 10s get nodes $NODE_NAME -o jsonpath="${NODE_READY_JSONPATH}" | grep True) ; then
            log Node $NODE_NAME is ready.
            break
        else
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log Node $NODE_NAME was not ready before timeout.
                fail
            fi
            echo -n .
            sleep 15
        fi
    done

    set -x
}
