#!/bin/bash
# Copyright 2017 AT&T Intellectual Property.  All other rights reserved.
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


set -eux

HTK_REPO=${HTK_REPO:-"https://opendev.org/openstack/openstack-helm-infra.git"}
HTK_STABLE_COMMIT=${HTK_COMMIT:-"d0c93b5648704b9d9999412d932f8329c80362c0"}



TMP_DIR=$(mktemp -d)

{
    HTK_REPO_DIR=$TMP_DIR/htk
    git clone "$HTK_REPO" "$HTK_REPO_DIR"
    (cd "$HTK_REPO_DIR" && git fetch --depth=1 "$HTK_REPO" "$HTK_STABLE_COMMIT" && git checkout FETCH_HEAD)
    cp -r "${HTK_REPO_DIR}/helm-toolkit" charts/deps/
}

rm -rf "${TMP_DIR}"
