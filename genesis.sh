#!/usr/bin/env bash

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi


set -ex

#Set working directory relative to script
SCRIPT_DIR=$(dirname $0)
pushd $SCRIPT_DIR

#Load Variables File
. variables.sh

mkdir -p /etc/docker
cat <<EOS > /etc/docker/daemon.json
{
  "live-restore": true,
  "storage-driver": "overlay2"
}
EOS

#Configuration for Docker Behind a Proxy
if [ $USE_PROXY == true ]; then
  mkdir -p /etc/systemd/system/docker.service.d
  CreateProxyConfiguraton
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    docker.io=$DOCKER_VERSION \


if [ -f "${PROMENADE_LOAD_IMAGE}" ]; then
  echo === Loading updated promenade image ===
  docker load -i "${PROMENADE_LOAD_IMAGE}"
fi

docker run -t --rm \
    --net host \
    -v /:/target \
    quay.io/attcomdev/promenade:experimental \
    promenade \
        -v \
        genesis \
            --hostname $(hostname) \
            --config-path /target$(realpath $1) 2>&1
