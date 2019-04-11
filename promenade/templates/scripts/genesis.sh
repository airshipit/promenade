{% include "header.sh" with context %}

{% include "basic-host-validation.sh" with context %}

{% include "up.sh" with context %}

mkdir -p /var/log/armada
touch /var/log/armada/bootstrap-armada.log
chmod 777 /var/log/armada/bootstrap-armada.log

chmod -R 600 /etc/genesis

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

while [[ ! -e /var/log/armada/bootstrap-armada.log ]]; do
    sleep 5
done
tail -f /var/log/armada/bootstrap-armada.log &

set +x
while true; do
    if [[ -e /etc/kubernetes/manifests/bootstrap-armada.yaml ]]; then
        sleep 30
        kubectl get pods --all-namespaces || echo "Could not get current pod status."
    else
        log Armada bootstrap manifest deployed
        break
    fi
done
set -x

# Terminate background job (tear down exit trap?)
kill %1

set +x
log
log === Waiting for Node to be Ready ===
set -x
wait_for_node_ready {{ config['Genesis:hostname'] }} 3600

{% include "cleanup.sh" with context %}

set +x
log
log === Finished genesis process ===
