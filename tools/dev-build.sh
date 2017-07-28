#!/usr/bin/env bash

set -ex

echo === Cleaning up old data ===
rm -rf promenade.tar configs
mkdir configs

echo === Building image ===
docker build -t quay.io/attcomdev/promenade:latest .

echo === Generating updated configuration ===
docker run --rm -t \
    -v $(pwd):/target quay.io/attcomdev/promenade:latest \
        promenade -v \
            generate \
                -c /target/example/vagrant-input-config.yaml \
                -o /target/configs

echo === Saving image ===
docker save -o promenade.tar quay.io/attcomdev/promenade:latest

echo === Done ===
