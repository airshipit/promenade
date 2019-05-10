#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

cd "${TEMP_DIR}"
mkdir scripts
chmod 777 scripts

PROMENADE_TMP_LOCAL="$(basename "$PROMENADE_TMP_LOCAL")"
PROMENADE_TMP="${TEMP_DIR}/${PROMENADE_TMP_LOCAL}"
mkdir -p "$PROMENADE_TMP"
chmod 777 "$PROMENADE_TMP"

DOCKER_SOCK="/var/run/docker.sock"
sudo chmod o+rw $DOCKER_SOCK

log Building scripts
docker run --rm -t \
    -w /target \
    -v "${TEMP_DIR}:/target" \
    -v "${PROMENADE_TMP}:/${PROMENADE_TMP_LOCAL}" \
    -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
    -e "DOCKER_HOST=unix:/${DOCKER_SOCK}" \
    -e "PROMENADE_TMP=${PROMENADE_TMP}" \
    -e "PROMENADE_TMP_LOCAL=/${PROMENADE_TMP_LOCAL}" \
    -e "PROMENADE_DEBUG=${PROMENADE_DEBUG}" \
    -e "PROMENADE_ENCRYPTION_KEY=${PROMENADE_ENCRYPTION_KEY}" \
    "${IMAGE_PROMENADE}" \
        promenade \
            build-all \
                --validators \
                -o scripts \
                config/*.yaml

sudo chmod o-rw $DOCKER_SOCK
