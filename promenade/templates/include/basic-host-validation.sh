# Validate the hostname is as expected
#
if [ "$(hostname)" != "{{ config.get_first('KubernetesNode:hostname', 'Genesis:hostname') }}" ]; then
   echo "The node hostname must match the Kubernetes node name" 1>&2
   exit 1
fi
