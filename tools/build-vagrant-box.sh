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

sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04-server-amd64.iso#http://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.1-server-amd64.iso' ubuntu.json

sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04-server-amd64.iso#http
://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.1-server-amd64.iso' ubun
tu-vagrant.json

sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04.2-server-amd64.iso#http
://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.2-server-amd64.iso' ubun
tu1604.json

packer build -var-file=ubuntu1604.json ubuntu-vagrant.json

vagrant box add promenade/ubuntu1604 box/libvirt/ubuntu1604-1.box
