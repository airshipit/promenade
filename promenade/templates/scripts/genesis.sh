{% include "header.sh" with context %}

{% include "up.sh" with context %}

set +x
log
log === Waiting for Kubernetes API availablity ===
set -x
wait_for_kubernetes_api 3600

{%- if config['Genesis:labels.dynamic']  is defined %}
set +x
log
log === Registering dynamic labels for node ===
set -x
register_labels {{ config['Genesis:hostname'] }} 3600 {{ config['Genesis:labels.dynamic'] | join(' ') }}
{%- endif %}

set +x
log
log === Deploying bootstrap manifest via Armada ===
set -x

while true; do
    sleep 10
    if armada apply --debug /etc/genesis/armada/assets/manifest.yaml ; then
        break
    fi
done

set +x
log
log === Waiting for Node to be Ready ===
set -x
wait_for_node_ready {{ config['Genesis:hostname'] }} 3600

{% include "cleanup.sh" with context %}

set +x
log
log === Finished genesis process ===
