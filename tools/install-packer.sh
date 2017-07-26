#!/usr/bin/env bash

set -ex

PACKER_VERSION=${PACKER_VERSION:-1.0.3}

WORKDIR=$(mktemp -d)

function cleanup {
    rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cd ${WORKDIR}

curl -Lo packer.zip https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip

unzip packer.zip

sudo mv packer /usr/local/bin/
