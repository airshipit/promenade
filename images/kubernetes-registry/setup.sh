#!/bin/bash
# Copyright 2025 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euxo pipefail

# Inbound variables
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.33.3"}
KUBERNETES_REGISTRY="registry.k8s.io"
CONSTANTS_URL="https://raw.githubusercontent.com/kubernetes/kubernetes/refs/tags/${KUBERNETES_VERSION}/cmd/kubeadm/app/constants/constants.go"

USE_PROXY=${USE_PROXY:-"false"}
GITHUB_PROXY=${GITHUB_PROXY:-""}

REGISTRY_IMAGE=${REGISTRY_IMAGE:-"quay.io/airshipit/registry:latest"}
REGISTRY_PORT=${REGISTRY_PORT:-"$(shuf -i 5050-5099 -n 1)"}
REGISTRY_VERSION=${REGISTRY_VERSION:-"3.0.0"}
REGISTRY_DOWNLOAD_URL="https://github.com/distribution/distribution/releases/download/v${REGISTRY_VERSION}/registry_${REGISTRY_VERSION}_linux_amd64.tar.gz"
DOCKER_REGISTRY_URL="localhost:$REGISTRY_PORT"
REGISTRY_DIR="$(dirname "$0")/assets/registry_dir"
REGISTRY_CID=""

declare -a CONTROL_PLANE_IMAGES=(
  "kube-apiserver"
  "kube-controller-manager"
  "kube-scheduler"
  "kube-proxy"
  "pause"
  "etcd"
  "coredns/coredns"
)

CLEANUP_REPO=false
CLEANUP_IMAGES=""

cleanup() {
  if [ "$CLEANUP_REPO" = true ]; then
    rm -rf "$REGISTRY_DIR"
  fi
  if [ -n "$REGISTRY_CID" ]; then
    docker stop "$REGISTRY_CID" || true
    docker rm "$REGISTRY_CID" || true
  fi
  for img in $CLEANUP_IMAGES; do
    docker rmi -f "$img" || true
  done
}
trap 'cleanup' EXIT

ensure_docker() {
  if which docker; then
    return
  fi
  apt-get install -y docker.io
}

curl() {
  if [[ $USE_PROXY == true ]]; then
    $(which curl) -x "http://$GITHUB_PROXY" "$@"
  else
    $(which curl) "$@"
  fi
}

ensure_docker
mkdir -p "$REGISTRY_DIR"
REGISTRY_CID=$(docker run -d -p "$REGISTRY_PORT":5000 -v "$REGISTRY_DIR:/var/lib/registry:rw" "$REGISTRY_IMAGE")

PAUSE_VERSION=$(curl -k -sL "${CONSTANTS_URL}" | grep "PauseVersion =" | awk -F' = ' '{gsub(/"/, "", $2); print $2}')
ETCD_VERSION=$(curl -k -sL "${CONSTANTS_URL}" | grep "DefaultEtcdVersion =" | awk -F'=' '{gsub(/"/, "", $2); gsub(/^[ \t]+/, "", $2);  print $2}')
COREDNS_VERSION=$(curl -k -sL "${CONSTANTS_URL}" | grep "CoreDNSVersion =" | awk -F'=' '{gsub(/"/, "", $2); gsub(/^[ \t]+/, "", $2);  print $2}')

for image in "${CONTROL_PLANE_IMAGES[@]}"; do
    tag="$KUBERNETES_VERSION"
    case "$image" in
        pause)
            tag="$PAUSE_VERSION"
            ;;
        etcd)
            tag="$ETCD_VERSION"
            ;;
        coredns*)
            tag="$COREDNS_VERSION"
            ;;
    esac

    echo "... Processing $image, tag $tag ..."
    docker pull "$KUBERNETES_REGISTRY/$image:$tag"
    docker tag "$KUBERNETES_REGISTRY/$image:$tag" "$DOCKER_REGISTRY_URL/$image:$tag"
    docker push "$DOCKER_REGISTRY_URL/$image:$tag"

    CLEANUP_IMAGES+="$KUBERNETES_REGISTRY/$image:$tag $DOCKER_REGISTRY_URL/$image:$tag "
    sleep 1
done

curl -sL "$REGISTRY_DOWNLOAD_URL" | tar -zC "$(dirname "$0")/assets" -x "registry"
