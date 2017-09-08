{% include "header.sh" with context %}

for node in $(kubectl get nodes -o name | cut -d / -f 2); do
    validate_kubectl_logs $node
done
