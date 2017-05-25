#!/bin/bash
#
# Copyright 2017 The Promenade Authors.
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

set -ex

source ./scripts/env.sh
source ./scripts/func.sh

validate_environment
# XXX validate_genesis_assets

if [ -f "genesis_image_cache/genesis-images.tar" ]; then
  docker load -i ./genesis-images.tar
else
  echo "Image Cache Not Found.. Skipping."
fi

install_assets
install_cni
install_kubelet

docker run --rm \
    -v /etc/kubernetes:/etc/kubernetes \
    quay.io/coreos/bootkube:${BOOTKUBE_VERSION} \
    /bootkube start \
        --asset-dir=/etc/kubernetes
