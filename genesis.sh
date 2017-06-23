#!/usr/bin/env bash

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi


set -ex

#Promenade Variables
DOCKER_PACKAGE="docker.io"
DOCKER_VERSION=1.12.6-0ubuntu1~16.04.1

#Proxy Variables
DOCKER_HTTP_PROXY=${DOCKER_HTTP_PROXY:-${HTTP_PROXY:-${http_proxy}}}
DOCKER_HTTPS_PROXY=${DOCKER_HTTPS_PROXY:-${HTTPS_PROXY:-${https_proxy}}}
DOCKER_NO_PROXY=${DOCKER_NO_PROXY:-${NO_PROXY:-${no_proxy}}}


mkdir -p /etc/docker
cat <<EOS > /etc/docker/daemon.json
{
  "live-restore": true,
  "storage-driver": "overlay2"
}
EOS

#Configuration for Docker Behind a Proxy
mkdir -p /etc/systemd/system/docker.service.d

#Set HTTPS Proxy Variable
cat <<EOF > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${DOCKER_HTTP_PROXY}"
EOF

#Set HTTPS Proxy Variable
cat <<EOF > /etc/systemd/system/docker.service.d/https-proxy.conf
[Service]
Environment="HTTPS_PROXY=${DOCKER_HTTPS_PROXY}"
EOF

#Set No Proxy Variable
cat <<EOF > /etc/systemd/system/docker.service.d/no-proxy.conf
[Service]
Environment="NO_PROXY=${DOCKER_NO_PROXY}"
EOF

#Reload systemd and docker if present
systemctl daemon-reload
systemctl restart docker || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    $DOCKER_PACKAGE=$DOCKER_VERSION \


if [ -f "${PROMENADE_LOAD_IMAGE}" ]; then
  echo === Loading updated promenade image ===
  docker load -i "${PROMENADE_LOAD_IMAGE}"
fi

docker pull quay.io/attcomdev/promenade:experimental
docker run -t --rm \
    --net host \
    -v /:/target \
    quay.io/attcomdev/promenade:experimental \
    promenade \
        -v \
        genesis \
            --hostname $(hostname) \
            --config-path /target$(realpath $1) 2>&1

touch /var/lib/prom.done
