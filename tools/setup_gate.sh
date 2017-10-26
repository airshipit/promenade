#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath $(dirname $0))
export WORKSPACE=$(realpath ${SCRIPT_DIR}/..)
export GATE_UTILS=${WORKSPACE}/tools/g2/lib/all.sh

export GATE_COLOR=${GATE_COLOR:-1}

source ${GATE_UTILS}

REQUIRE_RELOG=0

log_stage_header "Installing Packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -q -y --no-install-recommends \
    curl \
    docker.io \
    genisoimage \
    jq \
    libvirt-bin \
    qemu-kvm \
    qemu-utils \
    virtinst

log_stage_header "Joining User Groups"
for grp in docker libvirtd; do
    if ! groups | grep $grp > /dev/null; then
        sudo adduser `id -un` $grp
        REQUIRE_RELOG=1
    fi
done

log_stage_header "Setting Kernel Parameters"
if [ "xY" != "x$(cat /sys/module/kvm_intel/parameters/nested)" ]; then
    log_note Enabling nested virtualization.
    sudo modprobe -r kvm_intel
    sudo modprobe kvm_intel nested=1
    echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf
fi

if ! sudo virt-host-validate qemu &> /dev/null; then
    log_note Host did not validate virtualization check:
    sudo virt-host-validate qemu || true
fi

if [ ! -d ${VIRSH_POOL_PATH} ]; then
    sudo mkdir -p ${VIRSH_POOL_PATH}
fi

if [ $REQUIRE_RELOG -eq 1 ]; then
    echo
    log_note You must ${C_HEADER}log out${C_CLEAR} and back in before the gate is ready to run.
fi

log_huge_success
