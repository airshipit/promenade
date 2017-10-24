#!/usr/bin/env bash

set -e

source ${GATE_UTILS}

promenade_teardown_node ${GENESIS_NAME} n1

vm_clean ${GENESIS_NAME}
vm_create ${GENESIS_NAME}

rsync_cmd ${TEMP_DIR}/scripts/*${GENESIS_NAME}* ${GENESIS_NAME}:/root/promenade/

ssh_cmd ${GENESIS_NAME} /root/promenade/join-${GENESIS_NAME}.sh
ssh_cmd ${GENESIS_NAME} /root/promenade/validate-${GENESIS_NAME}.sh

validate_cluster n1

validate_etcd_membership kubernetes n1 n1 n2 n3
validate_etcd_membership calico n1 n1 n2 n3
