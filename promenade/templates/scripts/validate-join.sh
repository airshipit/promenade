{% include "header.sh" with context %}

validate_kubectl_logs {{ config['KubernetesNode:hostname'] }}
