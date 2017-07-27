#!/usr/bin/env bash

set -ex

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    nfs-common \
    nfs-kernel-server \
    portmap
