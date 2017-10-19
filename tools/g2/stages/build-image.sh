#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

log Building docker image ${IMAGE_PROMENADE}
sudo docker build -q -t ${IMAGE_PROMENADE} ${WORKSPACE}
