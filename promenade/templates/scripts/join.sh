if [ "$(hostname)" != "{{ config['KubernetesNode:hostname'] }}" ]; then
   echo "The node hostname must match the Kubernetes node name" 1>&2
   exit 1
fi

{% include "header.sh" with context %}

{% include "up.sh" with context %}

set +x
log
log === Waiting for Node to be Ready ===
set -x
wait_for_node_ready {{ config['KubernetesNode:hostname'] }} 3600

{%- if config['KubernetesNode:labels.dynamic']  is defined %}
set +x
log
log === Registering dynamic labels for node ===
set -x
register_labels {{ config['KubernetesNode:hostname'] }} 3600 {{ config['KubernetesNode:labels.dynamic'] | join(' ') }}
{%- endif %}

sleep 60

{% include "cleanup.sh" with context %}

set +x
log
log === Finished join process ===
