kubectl_cmd() {
    VIA=${1}

    shift

    ssh_cmd ${VIA} kubectl ${@}
}
