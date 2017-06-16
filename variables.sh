#!/bin/bash

#Promenade Variables
DOCKER_VERSION=1.12.6-0ubuntu1~16.04.1
PROMENADE_LOAD_IMAGE=$SCRIPT_DIR/promenade.tar

#HTTP Proxy Variables
USE_PROXY=false
DOCKER_HTTP_PROXY="http://proxy.server.com:8080"
DOCKER_HTTPS_PROXY="https://proxy.server.com:8080"
DOCKER_NO_PROXY="localhost,127.0.0.1"

function CreateProxyConfiguraton {
  #Set HTTP Proxy variable
  cat <<EOF > /etc/systemd/system/docker.service.d/http-proxy.conf
  [Service]
  Environment="HTTP_PROXY=${DOCKER_HTTPS_PROXY}"
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

}
