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

FROM python:3.6

VOLUME /etc/promenade
VOLUME /target

RUN mkdir /promenade
WORKDIR /promenade

RUN set -ex \
    && curl -Lo /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 \
    && chmod 555 /usr/local/bin/cfssl \
    && apt-get update -q \
    && apt-get install --no-install-recommends -y \
        libyaml-dev \
        rsync \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-frozen.txt /promenade
RUN pip install --no-cache-dir -r requirements-frozen.txt

COPY . /promenade
RUN pip install -e /promenade
