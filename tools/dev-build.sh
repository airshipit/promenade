#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(realpath $(dirname $0))
SOURCE_DIR=$(realpath $SCRIPT_DIR/..)

echo === Building image ===
docker build -t quay.io/airshipit/promenade:master ${SOURCE_DIR}

export PROMENADE_DEBUG=${PROMENADE_DEBUG:-1}

exec $SCRIPT_DIR/simple-deployment.sh ${@}
