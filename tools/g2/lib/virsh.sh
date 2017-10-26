img_base_declare() {
    log Validating base image exists
    if ! virsh vol-key --pool ${VIRSH_POOL} --vol promenade-base.img > /dev/null; then
        log Installing base image from ${BASE_IMAGE_URL}

        cd ${TEMP_DIR}
        curl -q -L -o base.img ${BASE_IMAGE_URL}

        virsh vol-create-as \
            --pool ${VIRSH_POOL} \
            --name promenade-base.img \
            --format qcow2 \
            --capacity ${BASE_IMAGE_SIZE} \
            --prealloc-metadata &>> ${LOG_FILE}

        virsh vol-upload \
            --vol promenade-base.img \
            --file base.img \
            --pool ${VIRSH_POOL} &>> ${LOG_FILE}
    fi
}

iso_gen() {
    NAME=${1}

    if virsh vol-key --pool ${VIRSH_POOL} --vol cloud-init-${NAME}.iso &> /dev/null; then
        log Removing existing cloud-init ISO for ${NAME}
        virsh vol-delete \
            --pool ${VIRSH_POOL} \
            --vol cloud-init-${NAME}.iso &>> ${LOG_FILE}
    fi

    log Creating cloud-init ISO for ${NAME}
    ISO_DIR=${TEMP_DIR}/iso/${NAME}
    mkdir -p ${ISO_DIR}
    cd ${ISO_DIR}

    export BR_IP_NODE=$(config_vm_ip ${NAME})
    export NAME
    export SSH_PUBLIC_KEY=$(ssh_load_pubkey)
    envsubst < ${TEMPLATE_DIR}/user-data.sub > user-data
    envsubst < ${TEMPLATE_DIR}/meta-data.sub > meta-data
    envsubst < ${TEMPLATE_DIR}/network-config.sub > network-config

    genisoimage \
        -V cidata \
        -input-charset utf-8 \
        -joliet \
        -rock \
        -o cidata.iso \
            meta-data \
            network-config \
            user-data &>> ${LOG_FILE}

    virsh vol-create-as \
        --pool ${VIRSH_POOL} \
        --name cloud-init-${NAME}.iso \
        --capacity $(stat -c %s ${ISO_DIR}/cidata.iso) \
        --format raw &>> ${LOG_FILE}

    virsh vol-upload \
        --pool ${VIRSH_POOL} \
        --vol cloud-init-${NAME}.iso \
        --file ${ISO_DIR}/cidata.iso &>> ${LOG_FILE}
}

iso_path() {
    NAME=${1}
    echo ${TEMP_DIR}/iso/${NAME}/cidata.iso
}

net_clean() {
    log net_clean is not yet implemented.
    exit 1
}

net_declare() {
    if ! virsh net-list --name | grep ^promenade$ > /dev/null; then
        log Creating promenade network
        virsh net-create ${XML_DIR}/network.xml &>> ${LOG_FILE}
    fi
}

pool_declare() {
    log Validating virsh pool setup
    if ! virsh pool-uuid ${VIRSH_POOL} &> /dev/null; then
        log Creating pool ${VIRSH_POOL}
        virsh pool-create-as --name ${VIRSH_POOL} --type dir --target ${VIRSH_POOL_PATH} &>> ${LOG_FILE}
    fi
}

vm_clean() {
    NAME=${1}
    if virsh list --name | grep ${NAME} &> /dev/null; then
        virsh destroy ${NAME} &>> ${LOG_FILE}
    fi

    if virsh list --name --all | grep ${NAME} &> /dev/null; then
        log Removing VM ${NAME}
        virsh undefine --remove-all-storage --domain ${NAME} &>> ${LOG_FILE}
    fi
}

vm_clean_all() {
    log Removing all VMs in parallel
    for NAME in ${ALL_VM_NAMES[@]}; do
        vm_clean ${NAME} &
    done
    wait
}

vm_create() {
    NAME=${1}
    iso_gen ${NAME}
    vol_create_root ${NAME}

    log Creating VM ${NAME}
    virt-install \
        --name ${NAME} \
        --virt-type kvm \
        --cpu host \
        --graphics vnc,listen=0.0.0.0 \
        --noautoconsole \
        --network network=promenade \
        --vcpus $(config_vm_vcpus) \
        --memory $(config_vm_memory) \
        --import \
        --disk vol=${VIRSH_POOL}/promenade-${NAME}.img,format=qcow2,bus=virtio \
        --disk pool=${VIRSH_POOL},size=20,format=qcow2,bus=virtio \
        --disk pool=${VIRSH_POOL},size=20,format=qcow2,bus=virtio \
        --disk vol=${VIRSH_POOL}/cloud-init-${NAME}.iso,device=cdrom &>> ${LOG_FILE}

    ssh_wait ${NAME}
    ssh_cmd ${NAME} sync
}

vm_create_all() {
    log Starting all VMs in parallel
    for NAME in $(config_vm_names); do
        vm_create ${NAME} &
    done
    wait

    for NAME in $(config_vm_names); do
        vm_validate ${NAME}
    done
}

vm_start() {
    NAME=${1}
    log Starting VM ${NAME}
    virsh start ${NAME} &>> ${LOG_FILE}
    ssh_wait ${NAME}
}

vm_stop() {
    NAME=${1}
    log Stopping VM ${NAME}
    virsh destroy ${NAME} &>> ${LOG_FILE}
}

vm_restart_all() {
    for NAME in $(config_vm_names); do
        vm_stop ${NAME} &
    done
    wait

    for NAME in $(config_vm_names); do
        vm_start ${NAME} &
    done
    wait
}

vm_validate() {
    NAME=${1}
    if ! virsh list --name | grep ${NAME} &> /dev/null; then
        log VM ${NAME} did not start correctly.
        exit 1
    fi
}


vol_create_root() {
    NAME=${1}

    if virsh vol-list --pool ${VIRSH_POOL} | grep promenade-${NAME}.img &> /dev/null; then
        log Deleting previous volume promenade-${NAME}.img
        virsh vol-delete --pool ${VIRSH_POOL} promenade-${NAME}.img &>> ${LOG_FILE}
    fi

    log Creating root volume for ${NAME}
    virsh vol-create-as \
        --pool ${VIRSH_POOL} \
        --name promenade-${NAME}.img \
        --capacity 64G \
        --format qcow2 \
        --backing-vol promenade-base.img \
        --backing-vol-format qcow2 &>> ${LOG_FILE}
}
