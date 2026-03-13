#!/usr/bin/env bash

set -eux

IMAGE_PROMENADE=${IMAGE_PROMENADE:-quay.io/airshipit/promenade:master}
PROMENADE_DEBUG=${PROMENADE_DEBUG:-0}

SCRIPT_DIR=$(realpath $(dirname $0))

# Keywords (generate-certs, build-all, replace) are extracted from any position.
# Remaining positional args: [CONFIG_SOURCE] [BUILD_DIR] [INTERFACE] [HOSTIP] [HOSTCIDR]
ACTION=""
REPLACE=false
ARGS=()
for arg in "$@"; do
    if [[ "${arg}" == "generate-certs" || "${arg}" == "build-all" ]]; then
        ACTION="${arg}"
    elif [[ "${arg}" == "replace" ]]; then
        REPLACE="replace"
    else
        ARGS+=("${arg}")
    fi
done

CONFIG_SOURCE=$(realpath ${ARGS[0]:-${SCRIPT_DIR}/../examples/basic})
BUILD_DIR=$(realpath ${ARGS[1]:-${SCRIPT_DIR}/../build})
HOSTNAME=$(hostname)
HOST_IFACE=$(ip route | grep "^default" | head -1 | awk '{ print $5 }')
INTERFACE=${ARGS[2]:-$HOST_IFACE}
HOSTIP=${ARGS[3]:-$(hostname -I | cut -d' ' -f 1)}
HOSTCIDR=${ARGS[4]:-"$(hostname -I | cut -d'.' -f 1,2,3).0\/24"}


# When ACTION is build-all only, skip cleanup/copy — BUILD_DIR must already
# contain the YAML configs and generated certificates from a prior run.
if [[ "${ACTION}" != "build-all" ]]; then
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
        sed -i "s/=ens3/=${INTERFACE}/g" "${BUILD_DIR}"/*.yaml
        sed -i "s/interface: ens3/interface: ${INTERFACE}/g" "${BUILD_DIR}"/*.yaml
    fi
else
    if [[ ! -d "${BUILD_DIR}" ]] || [[ -z "$(ls -A ${BUILD_DIR}/*.yaml 2>/dev/null)" ]]; then
        echo "ERROR: BUILD_DIR (${BUILD_DIR}) does not exist or contains no YAML files."
        echo "Run generate-certs first, or run without an action to do both steps."
        exit 1
    fi
fi

if [[ -z "${ACTION}" ]] || [[ "${ACTION}" = "generate-certs" ]]; then
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

if [[ -z "${ACTION}" ]] || [[ "${ACTION}" = "build-all" ]]; then
echo === Building bootstrap scripts ===
docker run --rm -t \
    -w /target \
    -e PROMENADE_DEBUG=$PROMENADE_DEBUG \
    -e http_proxy=${HTTP_PROXY:-} \
    -e https_proxy=${HTTPS_PROXY:-} \
    -e no_proxy=${NO_PROXY:-} \
    -v ${BUILD_DIR}:/target \
    ${IMAGE_PROMENADE} \
    promenade \
    build-all \
    -o /target \
    --validators \
    $(ls ${BUILD_DIR})
fi

echo === Done ===
