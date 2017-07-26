#!/usr/bin/env bash

set -ex

sudo apt-get update

sudo apt-get build-dep -y \
    ruby-libvirt

sudo apt-get install -y --no-install-recommends \
    build-essential \
    dnsmasq \
    ebtables \
    libvirt-bin \
    libvirt-dev \
    libxml2-dev \
    libxslt-dev \
    qemu \
    ruby-dev \
    zlib1g-dev

vagrant plugin install vagrant-libvirt
