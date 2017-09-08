#!/usr/bin/env bash

set -ex

SCRIPT_DIR=$(dirname $0)

echo === Building image ===
docker build -t quay.io/attcomdev/promenade:latest $(realpath $SCRIPT_DIR/..)

export PROMENADE_DEBUG=${PROMENADE_DEBUG:-1}

exec $SCRIPT_DIR/build-example.sh
