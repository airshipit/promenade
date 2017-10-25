#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

rm -rf ${WORKSPACE}/conformance
mkdir -p ${WORKSPACE}/conformance

rsync_cmd ${WORKSPACE}/tools/g2/sonobuoy.yaml ${GENESIS_NAME}:/root/
ssh_cmd ${GENESIS_NAME} mkdir -p /mnt/sonobuoy
kubectl_apply ${GENESIS_NAME} /root/sonobuoy.yaml

kubectl_wait_for_pod ${GENESIS_NAME} heptio-sonobuoy sonobuoy 7200

FILENAME=$(ssh_cmd ${GENESIS_NAME} ls /mnt/sonobuoy)
rsync_cmd ${GENESIS_NAME}:/mnt/sonobuoy/${FILENAME} ${WORKSPACE}/conformance/sonobuoy.tgz
tar xf ${WORKSPACE}/conformance/sonobuoy.tgz -C ${WORKSPACE}/conformance

tail -n 1 conformance/plugins/e2e/results/e2e.log | grep '^SUCCESS!'
