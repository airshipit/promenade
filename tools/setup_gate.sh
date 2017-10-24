#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath $(dirname $0))
export WORKSPACE=$(realpath ${SCRIPT_DIR}/..)
export GATE_UTILS=${WORKSPACE}/tools/g2/lib/all.sh

export GATE_COLOR=${GATE_COLOR:-1}

source ${GATE_UTILS}

REQUIRE_REBOOT=0
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
    if ! grep intel_iommu /etc/defaults/grub &> /dev/null; then
        log_note Enabling Intel IOMMU
        REQUIRE_REBOOT=1
        sudo mkdir -p /etc/defaults
        sudo touch /etc/defaults/grub
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} intel_iommu=on"' | sudo tee -a /etc/defaults/grub
    else
        echo -e ${C_ERROR}Failed to configure virtualization:${C_CLEAR}
        sudo virt-host-health qemu
        exit 1
    fi
fi

if [ ! -d ${VIRSH_POOL_PATH} ]; then
    sudo mkdir -p ${VIRSH_POOL_PATH}
fi

if [ $REQUIRE_REBOOT -eq 1 ]; then
    echo
    log_note You must ${C_HEADER}reboot${C_CLEAR} before for the gate is ready to run.
elif [ $REQUIRE_RELOG -eq 1 ]; then
    echo
    log_note You must ${C_HEADER}log out${C_CLEAR} and back in before the gate is ready to run.
fi

log_huge_success
