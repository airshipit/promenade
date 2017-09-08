#!/usr/bin/env bash

set -ex

REGISTRY_DATA_DIR=${REGISTRY_DATA_DIR:-/mnt/registry}

docker run -d \
    -p 5000:5000 \
    -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
    --restart=always \
    --name registry \
    -v $REGISTRY_DATA_DIR:/var/lib/registry \
        registry:2
