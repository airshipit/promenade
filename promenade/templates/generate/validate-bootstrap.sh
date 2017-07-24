{% include "common_validation.sh" with context %}

wait_for_ready_nodes 1

validate_kubectl_logs
