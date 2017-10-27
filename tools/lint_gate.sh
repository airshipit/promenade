#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath "$(dirname "${0}")")
WORKSPACE=$(realpath "${SCRIPT_DIR}/..")

for manifest in $(find "${WORKSPACE}/tools/g2/manifests" -type f | sort); do
    echo Checking "${manifest}"
    python -m jsonschema "${WORKSPACE}/tools/g2/manifest-schema.json" -i "${manifest}"
done
