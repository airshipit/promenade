#!/usr/bin/env bash

set -ex

GATE_DIR=$(realpath $(dirname $0))
pushd $GATE_DIR

ENV_PATH=$GATE_DIR/config-env
IMAGE_PROMENADE=${IMAGE_PROMENADE:-$1}

if [ ! -s $ENV_PATH ]; then
    echo Environment variables for config substitution in $ENV_PATH are required.
    exit 1
fi

if [ "x$IMAGE_PROMENADE" = "x" ]; then
    echo IMAGE_PROMENADE environment variable must be supplied.
    exit 1
fi

echo === Building assets for testing ===
echo Usinag image ${IMAGE_PROMENADE}.

echo === Cleaning up old data ===
rm -f config/*
rm -f promenade-bundle/*
mkdir -p config
chmod 777 config
mkdir -p promenade-bundle
chmod 777 promenade-bundle

echo === Validating test environment ===
env -i - $(cat default-config-env) env $(cat $ENV_PATH) $GATE_DIR/util/validate-test-env.sh

echo === Substituting variables into configuration ===
for template in config-templates/*; do
    OUTPUT_PATH=config/$(basename $template)
    env -i - $(cat default-config-env) env IMAGE_PROMENADE=$IMAGE_PROMENADE $(cat $ENV_PATH) envsubst < $template > $OUTPUT_PATH

    cat $OUTPUT_PATH
    echo
    echo
done

echo === Generating certificates ===
docker run --rm -t \
    -w /target \
    -v $GATE_DIR:/target \
    ${IMAGE_PROMENADE} \
        promenade \
            generate-certs \
                -o config \
                config/*.yaml

echo === Building genesis and join scripts
docker run --rm -t \
    -w /target \
    -v $GATE_DIR:/target \
    ${IMAGE_PROMENADE} \
        promenade \
            build-all \
                --validators \
                --leave-kubectl \
                -o promenade-bundle \
                config/*.yaml

echo === Bundling assets for delivery ===
cp $GATE_DIR/final-validation.sh promenade-bundle
tar czf promenade-bundle.tgz promenade-bundle/*

echo === Done ===
