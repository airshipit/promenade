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


sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04-server-amd64.iso#http://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.2-server-amd64.iso#g' ubuntu.json
sed -i -e 's/de5ee8665048f009577763efbf4a6f0558833e59/f529548fa7468f2d8413b8427d8e383b830df5f6/g' ubuntu.json
sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04.1-server-amd64.iso#http://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.2-server-amd64.iso#g' ubuntu-vagrant.json
sed -i -e 's/de5ee8665048f009577763efbf4a6f0558833e59/f529548fa7468f2d8413b8427d8e383b830df5f6/g' ubuntu-vagrant.json
sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04.3-server-amd64.iso#http://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.2-server-amd64.iso#g' ubuntu1604.json
sed -i -e 's/a06cd926f5855d4f21fb4bc9978a35312f815fbda0d0ef7fdc846861f4fc4600/737ae7041212c628de5751d15c3016058b0e833fdc32e7420209b76ca3d0a535/g' ubuntu1604.json
sed -i -e 's#http://releases.ubuntu.com/16.04/ubuntu-16.04-server-amd64.iso#http://old-releases.ubuntu.com/releases/xenial/ubuntu-16.04.1-server-amd64.iso#g' ubuntu.json

PACKER_LOG="yes" packer build -var-file=ubuntu1604.json ubuntu-vagrant.json

vagrant box add promenade/ubuntu1604 box/libvirt/ubuntu1604-1.box
