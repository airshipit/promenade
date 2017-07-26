#!/usr/bin/env bash

set -ex

WORKDIR=$(mktemp -d)

function cleanup {
    rm -rf "${WORKDIR}"
}

trap cleanup EXIT

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    curl \
    unzip

git clone https://github.com/jakobadam/packer-qemu-templates.git ${WORKDIR}

cd ${WORKDIR}/ubuntu

packer build -var-file=ubuntu1604.json ubuntu-vagrant.json

vagrant box add promenade/ubuntu1604 box/libvirt/ubuntu1604-1.box
