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

# Removes what setup.sh puts to the assets once the image of the registry is
# built from them. The images are built from the root of the repository and
# the images built next (promenade: COPY . ./) would get them too:
# - registry: the binary of the registry (a release of distribution), its CVEs
#   would be the ones of the promenade image too
# - registry_dir: the storage of the registry with the control plane images,
#   the promenade image doesn't need them
# config.yml stays: it is a file of the repository

set -euxo pipefail

ASSETS="$(dirname "$0")/assets"

rm -f "${ASSETS}/registry"
rm -rf "${ASSETS}/registry_dir"
