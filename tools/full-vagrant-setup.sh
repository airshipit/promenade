#!/usr/bin/env bash

set -ex

SCRIPT_DIR=$(dirname $0)

$SCRIPT_DIR/install-vagrant-nfs-deps.sh
$SCRIPT_DIR/install-vagrant-libvirt.sh
$SCRIPT_DIR/install-packer.sh
