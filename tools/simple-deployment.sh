#!/usr/bin/env bash

set -eux

IMAGE_PROMENADE=${IMAGE_PROMENADE:-quay.io/airshipit/promenade:master}
IMAGE_HYPERKUBE=${IMAGE_HYPERKUBE:-gcr.io/google_containers/hyperkube-amd64:v1.11.6}
PROMENADE_DEBUG=${PROMENADE_DEBUG:-0}

SCRIPT_DIR=$(realpath $(dirname $0))
CONFIG_SOURCE=$(realpath ${1:-${SCRIPT_DIR}/../examples/basic})
BUILD_DIR=$(realpath ${2:-${SCRIPT_DIR}/../build})
REPLACE=${3:-false}
HOSTNAME=$(hostname)
HOST_IFACE=$(ip route | grep "^default" | head -1 | awk '{ print $5 }')
# If not provided, interface is set to HOST_IFACE by default
INTERFACE=${4:-$HOST_IFACE}
# If not provided, it takes a guess at the host IP Address
HOSTIP=${5:-$(hostname -I | cut -d' ' -f 1)}
# Ceph CIDR provide like 10.0.0.0\\\/24
HOSTCIDR=${6:-"$(hostname -I | cut -d'.' -f 1,2,3).0\/24"}


echo === Cleaning up old data ===
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}
chmod 777 ${BUILD_DIR}

PROMENADE_TMP_LOCAL="$(basename "$PROMENADE_TMP_LOCAL")"
PROMENADE_TMP="${SCRIPT_DIR}/${PROMENADE_TMP_LOCAL}"
mkdir -p "$PROMENADE_TMP"
chmod 777 "$PROMENADE_TMP"

cp "${CONFIG_SOURCE}"/*.yaml ${BUILD_DIR}

if [ ${REPLACE} == 'replace' ]
then
    sed -i "s/-n0/-${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/- n0/- ${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/: n0/: ${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/:n0/:${HOSTNAME}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/192.168.77.10/${HOSTIP}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/192.168.77.0\/24/${HOSTCIDR}/g" "${BUILD_DIR}"/*.yaml
    sed -i "s/=ens3/=${INTERFACE}/g" "${BUILD_DIR}"/*.yaml
fi

if [[ -z $1 ]] || [[ $1 = generate-certs ]]; then
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
fi

if [[ -z $1 ]] || [[ $1 = build-all ]]; then
echo === Prepare hyperkube ===
docker run --rm -t \
    -v "${PROMENADE_TMP}:/tmp/${PROMENADE_TMP_LOCAL}" \
    "${IMAGE_HYPERKUBE}" \
        cp /hyperkube "/tmp/${PROMENADE_TMP_LOCAL}"

echo === Building bootstrap scripts ===
docker run --rm -t \
    -w /target \
    -e PROMENADE_DEBUG=$PROMENADE_DEBUG \
    -e http_proxy=${HTTP_PROXY} \
    -e https_proxy=${HTTPS_PROXY} \
    -e no_proxy=${NO_PROXY} \
    -v "${PROMENADE_TMP}:/tmp/${PROMENADE_TMP_LOCAL}" \
    -v ${BUILD_DIR}:/target \
    ${IMAGE_PROMENADE} \
    promenade \
    build-all \
    -o /target \
    --validators \
    $(ls ${BUILD_DIR})
fi

echo === Done ===
