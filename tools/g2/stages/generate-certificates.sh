#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

OUTPUT_DIR=${TEMP_DIR}/config
mkdir -p ${OUTPUT_DIR}

log Copying example configuration
cp ${WORKSPACE}/example/*.yaml ${OUTPUT_DIR}

registry_replace_references ${OUTPUT_DIR}/*.yaml

log Generating certificates
sudo docker run --rm -t \
    -w /target \
    -v ${OUTPUT_DIR}:/target \
    -e PROMENADE_DEBUG=${PROMENADE_DEBUG} \
    ${IMAGE_PROMENADE} \
        promenade \
            generate-certs \
                -o /target \
                $(ls ${OUTPUT_DIR})
