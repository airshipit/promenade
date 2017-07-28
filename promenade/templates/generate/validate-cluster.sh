{% include "common_validation.sh" with context %}

EXPECTED_NODE_COUNT={{ config['Cluster']['nodes'] | length }}
wait_for_ready_nodes $EXPECTED_NODE_COUNT

validate_kubectl_logs
