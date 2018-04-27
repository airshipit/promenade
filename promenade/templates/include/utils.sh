if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

set -x

export KUBECONFIG=/etc/kubernetes/admin/kubeconfig.yaml

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
    kubectl --request-timeout 15s get nodes 1>&2
    kubectl --request-timeout 15s get --all-namespaces pods -o wide 1>&2
}

function fail {
    set +e
    report_docker_state
    report_kube_state
    exit 1
}

function wait_for_ready_nodes {
    set +x

    NODES=$1
    SEC=${2:-600}

    log Waiting $SEC seconds for $NODES Ready nodes.

    NODE_READY_JSONPATH='{.items[*].status.conditions[?(@.type=="Ready")].status}'

    end=$(($(date +%s) + $SEC))
    while true; do
        READY_NODE_COUNT=$(kubectl --request-timeout 10s get nodes -o jsonpath="${NODE_READY_JSONPATH}" | tr ' ' '\n' | grep True | wc -l)
        if [ $NODES -gt $READY_NODE_COUNT ]; then
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log Nodes were not all ready before timeout.
                fail
            fi
            echo -n .
            sleep 5
        else
            log Found expected nodes.
            break
        fi
    done

    set -x
}

function wait_for_node_ready {
    set +x

    NODE_NAME=$1
    SEC=${2:-3600}

    log Waiting $SEC seconds for $NODE_NAME to be ready.

    NODE_READY_JSONPATH='{.status.conditions[?(@.type=="Ready")].status}'

    end=$(($(date +%s) + $SEC))
    while true; do
        if (kubectl --request-timeout 10s get nodes $NODE_NAME -o jsonpath="${NODE_READY_JSONPATH}" | grep True) ; then
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

    {%- if config['KubernetesNetwork:dns.bootstrap_validation_checks'] is defined %}
    REQUIRED_DNS_LOOKUPS=(
        {%- for domain in config['KubernetesNetwork:dns.bootstrap_validation_checks'] %}
        {{ domain }}
        {%- endfor %}
    )
    log Waiting $SEC seconds for specified DNS queries to work:
    for DOMAIN in ${REQUIRED_DNS_LOOKUPS[*]}; do
        log $DOMAIN
    done

    while true; do
        SUCCESS=1
        for DOMAIN in ${REQUIRED_DNS_LOOKUPS[*]}; do
            if ! (dig $DOMAIN > /dev/null 2> /dev/nul); then
                SUCCESS=0
                log Failed to resolve $DOMAIN
                break
            fi
        done

        if [ $SUCCESS -eq 1 ]; then
            log Resolved specified queries.
            break
        fi
        now=$(date +%s)
        if [ $now -gt $end ]; then
            log Could not resolve all required DNS names by timeout on $NODE.
            fail
        fi
        sleep 15
    done
    {%- endif %}

    set -x
}

function wait_for_kubernetes_api {
    set +x

    SEC=${1:-3600}

    log Waiting $SEC seconds for API response.

    end=$(($(date +%s) + $SEC))
    while true; do
        if kubectl --request-timeout 5s get nodes 2>&1 > /dev/null; then
            echo 1>&2
            log Got response from Kubernetes API.
            break
        else
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log API not returning node list before timeout.
                fail
            fi
            echo -n . 1>&2
            sleep 15
        fi
    done

    set -x
}

function register_labels {
    set +x
    NODE=$1
    TIMEOUT=$2
    shift 2

    LABELS="$@"

    end=$(($(date +%s) + $SEC))
    while true; do
        if kubectl label node $NODE --overwrite $LABELS ; then
            echo 1>&2
            log Applied labels $LABELS on $NODE
            break
        else
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log Failed to apply labels $LABELS on $NODE
                fail
            fi
            echo -n . 1>&2
            sleep 15
        fi
    done
    set -x
}

function wait_for_pod_termination {
    set +x

    NAMESPACE=$1
    POD_NAME=$2
    SEC=${3:-300}

    log Waiting $SEC seconds for termination of pod $POD_NAME

    POD_PHASE_JSONPATH='{.status.phase}'

    end=$(($(date +%s) + $SEC))
    while true; do
        POD_PHASE=$(kubectl --request-timeout 10s --namespace $NAMESPACE get -a -o jsonpath="${POD_PHASE_JSONPATH}" pod $POD_NAME)
        if [ "x$POD_PHASE" = "xSucceeded" ]; then
            log Pod $POD_NAME succeeded.
            break
        elif [ "x$POD_PHASE" = "xFailed" ]; then
            log Pod $POD_NAME failed.
            kubectl --request-timeout 10s --namespace $NAMESPACE get -a -o yaml pod $POD_NAME 1>&2
            fail
        else
            now=$(date +%s)
            if [ $now -gt $end ]; then
                log Pod did not terminate before timeout.
                kubectl --request-timeout 10s --namespace $NAMESPACE get -a -o yaml pod $POD_NAME 1>&2
                fail
            fi
            sleep 1
        fi
    done

    set -x
}

function validate_kubectl_logs {
    NODE=$1
    NAMESPACE=default
    POD_NAME=log-test-${NODE}-$(date +%s)

    cat <<EOPOD | kubectl --namespace $NAMESPACE apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: ${NODE}
  containers:
  - name: noisy
    image: busybox:1.28.3
    imagePullPolicy: IfNotPresent
    command:
    - /bin/echo
    - EXPECTED RESULT
...
EOPOD

    wait_for_node_ready $NODE 300
    wait_for_pod_termination $NAMESPACE $POD_NAME
    ACTUAL_LOGS=$(kubectl --namespace $NAMESPACE logs $POD_NAME)
    if [ "x$ACTUAL_LOGS" != "xEXPECTED RESULT" ]; then
        log Got unexpected logs:
        kubectl --namespace $NAMESPACE logs $POD_NAME 1>&2
        fail
    fi
}
