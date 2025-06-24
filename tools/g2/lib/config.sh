export TEMP_DIR=${TEMP_DIR:-$(mktemp -d)}
export BASE_IMAGE_SIZE=${BASE_IMAGE_SIZE:-644612096}
export BASE_IMAGE_URL=${BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img}
export IMAGE_PROMENADE=${IMAGE_PROMENADE:-quay.io/airshipit/promenade:master}
export IMAGE_PROMENADE_DISTRO=${IMAGE_PROMENADE_DISTRO:-ubuntu_jammy}
export NGINX_DIR="${TEMP_DIR}/nginx"
export NGINX_URL="http://192.168.77.1:7777"
export PROMENADE_BASE_URL="http://promenade-api.ucp.svc.cluster.local"
export PROMENADE_DEBUG=${PROMENADE_DEBUG:-0}
export PROMENADE_ENCRYPTION_KEY=${PROMENADE_ENCRYPTION_KEY:-testkey}
export REGISTRY_DATA_DIR=${REGISTRY_DATA_DIR:-/mnt/registry}
export VIRSH_POOL=${VIRSH_POOL:-promenade}
export VIRSH_POOL_PATH=${VIRSH_POOL_PATH:-/var/lib/libvirt/promenade}

config_configuration() {
    # XXX Do I need ' | @sh' now?
    jq -cr '.configuration[]' < "${GATE_MANIFEST}"
}

config_vm_memory() {
    jq -cr '.vm.memory' < "${GATE_MANIFEST}"
}

config_vm_names() {
    jq -cr '.vm.names[]' < "${GATE_MANIFEST}"
}

config_vm_ip() {
    NAME=${1}
    echo "192.168.77.1${NAME:1}"
}

config_vm_vcpus() {
    jq -cr '.vm.vcpus' < "${GATE_MANIFEST}"
}
