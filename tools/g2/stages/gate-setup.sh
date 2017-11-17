#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

# Docker registry (cache) setup
registry_up
registry_populate

# NginX for serving config files in the absence of Deckhand
nginx_down
nginx_up

# SSH setup
ssh_setup_declare

# Virsh setup
pool_declare
img_base_declare
net_declare
