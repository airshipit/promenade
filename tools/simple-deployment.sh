#!/usr/bin/env bash

set -eux

IMAGE_PROMENADE=${IMAGE_PROMENADE:-quay.io/airshipit/promenade:master}
PROMENADE_DEBUG=${PROMENADE_DEBUG:-0}

SCRIPT_DIR=$(realpath $(dirname $0))
CONFIG_SOURCE=$(realpath ${1:-${SCRIPT_DIR}/../examples/basic})
BUILD_DIR=$(realpath ${2:-${SCRIPT_DIR}/../build})
REPLACE=${3:-false}
HOSTNAME=$(hostname)
# If not provided, it takes a guess at the host IP Address
HOSTIP=${4:-$(hostname -I | cut -d' ' -f 1)}
# Ceph CIDR provide like 10.0.0.0\\\/24
HOSTCIDR=${5:-"$(hostname -I | cut -d'.' -f 1,2,3).0\/24"}


echo === Cleaning up old data ===
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}
chmod 777 ${BUILD_DIR}

cp "${CONFIG_SOURCE}"/*.yaml ${BUILD_DIR}

if [ ${REPLACE} == 'replace' ]
then
    sed -i "s/-n0/-${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/- n0/- ${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/: n0/: ${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/:n0/:${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/192.168.77.10/${HOSTIP}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/192.168.77.0\/24/${HOSTCIDR}/g" "${BUILD_DIR}"/*.yaml
fi

echo === Generating updated certificates ===
docker run --rm -t \
    -w /target \
    -e PROMENADE_DEBUG=$PROMENADE_DEBUG \
    -v ${BUILD_DIR}:/target \
    ${IMAGE_PROMENADE} \
        promenade \
            generate-certs \
                -o /target \
                $(ls ${BUILD_DIR})

echo === Building bootstrap scripts ===
docker run --rm -t \
    -w /target \
    -e PROMENADE_DEBUG=$PROMENADE_DEBUG \
    -v ${BUILD_DIR}:/target \
    ${IMAGE_PROMENADE} \
        promenade \
            build-all \
                -o /target \
                --validators \
                $(ls ${BUILD_DIR})

echo === Done ===
