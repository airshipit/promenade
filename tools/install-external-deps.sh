#!/bin/bash
# Installs external dependencies required for basic testing

set -ex

export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | sudo -En debconf-set-selections

CFSSL_URL=${CFSSL_URL:-https://pkg.cfssl.org/R1.2/cfssl_linux-amd64}

if [[ ! $(command -v cfssl) ]]; then
    TMP_DIR=$(mktemp -d)
    pushd "${TMP_DIR}"
    curl -Lo cfssl "${CFSSL_URL}"
    chmod 755 cfssl
    sudo -En mv cfssl /usr/local/bin/
    popd
    rm -rf "${TMP_DIR}"
    cfssl version
fi
