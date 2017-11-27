{% include "header.sh" with context %}

wait_for_kubernetes_api

for node in $(kubectl get nodes -o name | cut -d / -f 2); do
    wait_for_node_ready $node 180
    validate_kubectl_logs $node
done
