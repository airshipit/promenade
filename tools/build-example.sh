#!/usr/bin/env bash

set -ex

IMAGE_PROMENADE=${IMAGE_PROMENADE:-quay.io/attcomdev/promenade:latest}

echo === Cleaning up old data ===
rm -rf example/scripts
mkdir example/scripts

echo === Generating updated certificates ===
docker run --rm -t \
    -w /target \
    -e PROMENADE_DEBUG=$PROMENADE_DEBUG \
    -v $(pwd):/target \
    ${IMAGE_PROMENADE} \
        promenade \
            generate-certs \
                -o example \
                example/*.yaml

echo === Building bootstrap scripts ===
docker run --rm -t \
    -w /target \
    -e PROMENADE_DEBUG=$PROMENADE_DEBUG \
    -v $(pwd):/target \
    ${IMAGE_PROMENADE} \
        promenade \
            build-all \
                -o example/scripts \
                --validators \
                example/*.yaml

echo === Done ===
