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

ENV CNI_VERSION=v0.5.2 \
    HELM_VERSION=v2.4.2 \
    KUBECTL_VERSION=v1.6.2 \
    KUBELET_VERSION=v1.6.2

VOLUME /etc/promenade
VOLUME /target

RUN mkdir /promenade
WORKDIR /promenade

RUN set -ex \
    && export BIN_DIR=/assets/usr/local/bin \
    && mkdir -p $BIN_DIR \
    && curl -sLo $BIN_DIR/kubelet http://storage.googleapis.com/kubernetes-release/release/$KUBELET_VERSION/bin/linux/amd64/kubelet \
    && curl -sLo $BIN_DIR/kubectl http://storage.googleapis.com/kubernetes-release/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl \
    && chmod 555 $BIN_DIR/kubelet \
    && chmod 555 $BIN_DIR/kubectl \
    && mkdir -p /assets/opt/cni/bin \
    && curl -sL https://github.com/containernetworking/cni/releases/download/$CNI_VERSION/cni-amd64-$CNI_VERSION.tgz | tar -zxv -C /assets/opt/cni/bin/ \
    && curl -sL https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar -zxv -C /tmp linux-amd64/helm \
    && mv /tmp/linux-amd64/helm $BIN_DIR/helm \
    && chmod 555 $BIN_DIR/helm

RUN set -ex \
    && apt-get update -qq \
    && apt-get install --no-install-recommends -y \
        libyaml-dev \
        openssl \
        rsync \
    && rm -rf /var/lib/apt/lists/*

RUN set -ex \
    && curl -sLo /usr/local/bin/cfssl https://pkg.cfssl.org/R1.1/cfssl_linux-amd64 \
    && chmod 555 /usr/local/bin/cfssl \
    && curl -sLo /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.1/cfssljson_linux-amd64 \
    && chmod 555 /usr/local/bin/cfssljson

COPY requirements-frozen.txt /promenade
RUN pip install --no-cache-dir -r requirements-frozen.txt

COPY . /promenade
RUN pip install -e /promenade
