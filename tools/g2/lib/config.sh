export BASE_IMAGE_SIZE=${BASE_IMAGE_SIZE:-68719476736}
export BASE_IMAGE_URL=${BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/releases/16.04/release/ubuntu-16.04-server-cloudimg-amd64-disk1.img}
export IMAGE_PROMENADE=${IMAGE_PROMENADE:-quay.io/attcomdev/promenade:latest}
export PROMENADE_DEBUG=${PROMENADE_DEBUG:-0}
export REGISTRY_DATA_DIR=${REGISTRY_DATA_DIR:-/mnt/registry}
export VIRSH_POOL=${VIRSH_POOL:-promenade}
export VIRSH_POOL_PATH=${VIRSH_POOL_PATH:-/var/lib/libvirt/promenade}
