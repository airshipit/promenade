GENESIS_NAME=n0
SSH_CONFIG_DIR=${WORKSPACE}/tools/g2/config-ssh
TEMPLATE_DIR=${WORKSPACE}/tools/g2/templates
XML_DIR=${WORKSPACE}/tools/g2/xml
VM_NAMES=(
    n0
    n1
    n2
    n3
)

vm_ip() {
    NAME=${1}
    echo 192.168.77.1${NAME:1}
}
