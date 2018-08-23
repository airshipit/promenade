#!/bin/bash
# Installs external dependencies required for basic testing

set -ex

CFSSL_URL=${CFSSL_URL:-https://pkg.cfssl.org/R1.2/cfssl_linux-amd64}

if [[ ! $(which cfssl) ]]; then
    TMP_DIR=$(mktemp -d)
    pushd "${TMP_DIR}"
    curl -Lo cfssl "${CFSSL_URL}"
    chmod 755 cfssl
    sudo mv cfssl /usr/local/bin/
    popd
    rm -rf "${TMP_DIR}"
fi
