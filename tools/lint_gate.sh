#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(realpath "$(dirname "${0}")")
WORKSPACE=$(realpath "${SCRIPT_DIR}/..")

for manifest in $(find "${WORKSPACE}/tools/g2/manifests" -type f | sort); do
    echo Checking "${manifest}"
    python -m jsonschema "${WORKSPACE}/tools/g2/manifest-schema.json" -i "${manifest}"
done

if [[ -x $(which shellcheck) ]]; then
    echo Checking shell scripts..
    shellcheck -s bash -e SC2029 "${WORKSPACE}"/tools/cleanup.sh "${WORKSPACE}"/tools/*gate*.sh "${WORKSPACE}"/tools/g2/stages/* "${WORKSPACE}"/tools/g2/lib/* "${WORKSPACE}"/tools/install-external-deps.sh
else
    echo No shellcheck executable found.  Please, install it.
    exit 1
fi
