#!/usr/bin/env bash

set -eu

source "${GATE_UTILS}"

log Testing disk IO

fio \
    --randrepeat=1 \
    --ioengine=libaio \
    --direct=1 \
    --gtod_reduce=1 \
    --name=test \
    --filename=.fiotest \
    --bs=4k \
    --iodepth=64 \
    --size=1G \
    --readwrite=randrw \
    --rwmixread=50
