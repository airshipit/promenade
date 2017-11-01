#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

rm -rf ${WORKSPACE}/conformance
mkdir -p ${WORKSPACE}/conformance

rsync_cmd ${WORKSPACE}/tools/g2/sonobuoy.yaml ${GENESIS_NAME}:/root/
ssh_cmd ${GENESIS_NAME} mkdir -p /mnt/sonobuoy
kubectl_apply ${GENESIS_NAME} /root/sonobuoy.yaml

if kubectl_wait_for_pod ${GENESIS_NAME} heptio-sonobuoy sonobuoy 7200; then
    log Pod succeeded
    SUCCESS=1
else
    log Pod failed
    SUCCESS=0
fi

FILENAME=$(ssh_cmd ${GENESIS_NAME} ls /mnt/sonobuoy || echo "")
if [[ ! -z ${FILENAME} ]]; then
    if rsync_cmd ${GENESIS_NAME}:/mnt/sonobuoy/${FILENAME} ${WORKSPACE}/conformance/sonobuoy.tgz; then
        tar xf ${WORKSPACE}/conformance/sonobuoy.tgz -C ${WORKSPACE}/conformance
    fi
fi

if [[ ${SUCCESS} = "1" ]]; then
    tail -n 1 conformance/plugins/e2e/results/e2e.log | grep '^SUCCESS!'
else
    if [[ -s conformance/plugins/e2e/results/e2e.log ]]; then
        tail -n 50 conformance/plugins/e2e/results/e2e.log
        exit 1
    fi
fi
