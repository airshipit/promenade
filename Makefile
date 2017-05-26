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

#---------------#
# Configuration #
#---------------#
BOOTKUBE_VERSION := v0.4.1
CNI_VERSION := v0.5.2
HELM_VERSION := v2.3.1
KUBERNETES_VERSION := v1.6.2

NAMESPACE := quay.io/attcomdev
GENESIS_REPO := promenade-genesis
JOIN_REPO := promenade-join
TAG := dev

#PreFetch Images for Offline deployment
PREFETCH_IMAGES := false

GENESIS_IMAGES := \
	gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.1 \
	gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.1 \
	gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.1 \
	gcr.io/google_containers/pause-amd64:3.0 \
	quay.io/calico/cni:v1.7.0 \
	quay.io/calico/kube-policy-controller:v0.5.4 \
	quay.io/calico/node:v1.1.3 \
	quay.io/coreos/bootkube:$(BOOTKUBE_VERSION) \
	quay.io/coreos/etcd-operator:v0.2.5 \
	quay.io/coreos/etcd:v3.1.4 \
	quay.io/coreos/etcd:v3.1.6 \
	quay.io/coreos/flannel:v0.7.1 \
	quay.io/coreos/hyperkube:$(KUBERNETES_VERSION)_coreos.0 \
	quay.io/coreos/kenc:48b6feceeee56c657ea9263f47b6ea091e8d3035 \
	quay.io/coreos/pod-checkpointer:20cf8b9a6018731a0770192f30dfa7a1941521e3 \

JOIN_IMAGES := \
	gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.1 \
	gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.1 \
	gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.1 \
	gcr.io/google_containers/pause-amd64:3.0 \
	quay.io/calico/cni:v1.7.0 \
	quay.io/calico/kube-policy-controller:v0.5.4 \
	quay.io/calico/node:v1.1.3 \
	quay.io/coreos/etcd-operator:v0.2.5 \
	quay.io/coreos/etcd:v3.1.4 \
	quay.io/coreos/etcd:v3.1.6 \
	quay.io/coreos/flannel:v0.7.1 \
	quay.io/coreos/hyperkube:$(KUBERNETES_VERSION)_coreos.0 \
	quay.io/coreos/kenc:48b6feceeee56c657ea9263f47b6ea091e8d3035 \
	quay.io/coreos/pod-checkpointer:20cf8b9a6018731a0770192f30dfa7a1941521e3 \

#Build Deps
GENESIS_BUILD_DEPS := Dockerfile.genesis cni.tgz env.sh helm kubelet kubelet.service.template

ifeq ($(PREFETCH_IMAGES), true)
GENESIS_BUILD_DEPS += genesis_image_cache/genesis-images.tar
endif

JOIN_BUILD_DEPS := Dockerfile.join kubelet.service.template

ifeq ($(PREFETCH_IMAGES), true)
JOIN_BUILD_DEPS += join_image_cache/join-images.tar
endif

#-------#
# Rules #
#-------#
all: build

build: build-genesis build-join

push: push-genesis push-join

save: save-genesis save-join

genesis: build-genesis

build-genesis: $(GENESIS_BUILD_DEPS)
	sudo docker build -f Dockerfile.genesis -t $(NAMESPACE)/$(GENESIS_REPO):$(TAG) .


push-genesis: build-genesis
	sudo docker push $(NAMESPACE)/$(GENESIS_REPO):$(TAG)

save-genesis: build-genesis
	sudo docker save $(NAMESPACE)/$(GENESIS_REPO):$(TAG) > promenade-genesis.tar


join: build-join

build-join: $(JOIN_BUILD_DEPS)
	sudo docker build -f Dockerfile.join -t $(NAMESPACE)/$(JOIN_REPO):$(TAG) .

push-join: build-join
	sudo docker push $(NAMESPACE)/$(JOIN_REPO):$(TAG)

save-join: build-join
	sudo docker save $(NAMESPACE)/$(JOIN_REPO):$(TAG) > promenade-join.tar

cni.tgz:
	curl -Lo cni.tgz https://github.com/containernetworking/cni/releases/download/$(CNI_VERSION)/cni-amd64-$(CNI_VERSION).tgz

env.sh: Makefile
	rm -f env.sh
	echo export BOOTKUBE_VERSION=$(BOOTKUBE_VERSION) >> env.sh
	echo export CNI_VERSION=$(CNI_VERSION) >> env.sh
	echo export HELM_VERSION=$(HELM_VERSION) >> env.sh
	echo export KUBERNETES_VERSION=$(KUBERNETES_VERSION) >> env.sh

helm:
	curl -Lo helm.tgz https://storage.googleapis.com/kubernetes-helm/helm-$(HELM_VERSION)-linux-amd64.tar.gz
	tar xf helm.tgz
	mv linux-amd64/helm ./helm
	rm -rf ./linux-amd64/
	rm -f helm.tgz
	chmod +x helm

genesis_image_cache/genesis-images.tar:
	for IMAGE in $(GENESIS_IMAGES); do \
		sudo docker pull $$IMAGE; \
	done
	mkdir genesis_image_cache
	sudo docker save -o genesis_image_cache/genesis-images.tar $(GENESIS_IMAGES)

join_image_cache/join-images.tar:
	for IMAGE in $(JOIN_IMAGES); do \
		sudo docker pull $$IMAGE; \
	done
	mkdir join_image_cache
	sudo docker save -o join_image_cache/join-images.tar $(JOIN_IMAGES)

kubelet:
	curl -LO http://storage.googleapis.com/kubernetes-release/release/$(KUBERNETES_VERSION)/bin/linux/amd64/kubelet
	chmod +x kubelet

clean:
	rm -rf \
		*.tar \
		cni.tgz \
		env.sh \
		helm \
		helm.tgz \
		kubelet \
		linux-amd64 \
		genesis_image_cache \
		join_image_cache \


.PHONY : build build-genesis build-join clean genesis join push push-genesis push-join
