#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

cd ${TEMP_DIR}
mkdir scripts

log Building scripts
docker run --rm -t \
    -w /target \
    -v ${TEMP_DIR}:/target \
    -e PROMENADE_DEBUG=${PROMENADE_DEBUG} \
    ${IMAGE_PROMENADE} \
        promenade \
            build-all \
                --validators \
                -o scripts \
                config/*.yaml
