#!/usr/bin/env bash

set -ex

SCRIPT_DIR=$(dirname $0)
REQUIRED_VARIABLES_PATH=$(realpath $SCRIPT_DIR/../required-config-env)

env | sort

for varname in $(cat $REQUIRED_VARIABLES_PATH); do
    if [ "x${!varname}" = "x" ]; then
        echo Missing required variable: $varname
        exit 1
    fi
done
