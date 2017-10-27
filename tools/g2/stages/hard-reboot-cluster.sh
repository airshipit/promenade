#!/usr/bin/env bash

set -e

source "${GATE_UTILS}"

vm_restart_all
validate_cluster "${GENESIS_NAME}"
