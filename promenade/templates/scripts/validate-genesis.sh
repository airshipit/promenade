{% include "header.sh" with context %}

wait_for_kubernetes_api

validate_kubectl_logs {{ config['Genesis:hostname'] }}
