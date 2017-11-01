#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

log Building docker image "${IMAGE_PROMENADE}"
docker build -q -t "${IMAGE_PROMENADE}" "${WORKSPACE}"

log Loading Promenade image "${IMAGE_PROMENADE}" into local registry
docker tag "${IMAGE_PROMENADE}" "localhost:5000/${IMAGE_PROMENADE}" &>> "${LOG_FILE}"
docker push "localhost:5000/${IMAGE_PROMENADE}" &>> "${LOG_FILE}"
