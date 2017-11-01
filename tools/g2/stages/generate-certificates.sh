#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

OUTPUT_DIR="${TEMP_DIR}/config"
mkdir -p "${OUTPUT_DIR}"

for source_dir in $(config_configuration); do
    log Copying configuration from "${source_dir}"
    cp "${WORKSPACE}/${source_dir}"/*.yaml "${OUTPUT_DIR}"
done

registry_replace_references "${OUTPUT_DIR}"/*.yaml

FILES=($(ls "${OUTPUT_DIR}"))

log Generating certificates
docker run --rm -t \
    -w /target \
    -v "${OUTPUT_DIR}:/target" \
    -e "PROMENADE_DEBUG=${PROMENADE_DEBUG}" \
    "${IMAGE_PROMENADE}" \
        promenade \
            generate-certs \
                -o /target \
                "${FILES[@]}"
