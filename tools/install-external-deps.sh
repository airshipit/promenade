#!/bin/bash
# Installs external dependencies required for basic testing

set -ex

export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | sudo -En debconf-set-selections

if [[ ! $(command -v cfssl) ]]; then
    echo "Installing cfssl..."
    sudo apt-get update
    sudo apt-get install -y golang-cfssl
    sudo ln -s /usr/bin/cfssl /usr/local/bin/cfssl
    cfssl version
fi
