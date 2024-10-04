# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
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

BUILD_DIR         := $(shell mktemp -d)
DOCKER_REGISTRY   ?= quay.io
HELM              := $(BUILD_DIR)/helm
IMAGE_PREFIX      ?= airshipit
IMAGE_NAME        ?= promenade
IMAGE_TAG         ?= latest
PROXY             ?= http://proxy.foo.com:8000
NO_PROXY          ?= localhost,127.0.0.1,.svc.cluster.local
USE_PROXY         ?= false
PUSH_IMAGE        ?= false
# use this variable for image labels added in internal build process
LABEL             ?= org.airshipit.build=community
COMMIT            ?= $(shell git rev-parse HEAD)
DISTRO            ?= ubuntu_jammy
PYTHON            = python3
CHARTS            := $(filter-out deps, $(patsubst charts/%/.,%,$(wildcard charts/*/.)))
IMAGE             := ${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}-${DISTRO}
BASE_IMAGE        ?=

all: charts lint

tests: external-deps gate-lint
	tox

tests-security:
	tox -e bandit

docs: clean
	tox -e docs

tests-unit: external-deps
	tox -e py38

external-deps:
	export DEBIAN_FRONTEND=noninteractive
	./tools/install-external-deps.sh

tests-pep8:
	tox -e pep8

tests-freeze:
	tox -e freeze

chartbanner:
	@echo Building charts: $(CHARTS)

charts: $(CHARTS)
	@echo Done building charts.

helm-init: $(addprefix helm-init-,$(CHARTS))

helm-init-%: helm-toolkit
	@echo Initializing chart $*
	cd charts;if [ -s $*/requirements.yaml ]; then echo "Initializing $*";$(HELM) dep up --skip-refresh $*; fi

lint: helm-lint gate-lint

gate-lint: gate-lint-deps
	export DEBIAN_FRONTEND=noninteractive
	tox -e gate-lint

gate-lint-deps:
	sudo apt install -y --no-install-recommends shellcheck
	sudo pip3 install tox

helm-lint: $(addprefix helm-lint-,$(CHARTS))

helm-lint-%: helm-install helm-init-%
	@echo Linting chart $*
	cd charts
	$(HELM) dep up charts/$*
	$(HELM) lint charts/$*

images: check-docker build_promenade

check-docker:
	@if [ -z $$(which docker) ]; then \
		echo "Missing \`docker\` client which is required for development"; \
		exit 2; \
	fi

dry-run: $(addprefix dry-run-,$(CHARTS))

dry-run-%: helm-lint-%
	echo Running Dry-Run on chart $*
	cd charts;$(HELM) template --set pod.resources.enabled=true $*

$(CHARTS): $(addprefix dry-run-,$(CHARTS)) chartbanner
	$(HELM) package -d charts charts/$@

_BASE_IMAGE_ARG := $(if $(BASE_IMAGE),--build-arg FROM="${BASE_IMAGE}" ,)

build_promenade:
ifeq ($(USE_PROXY), true)
	docker build --network host -t $(IMAGE) --label $(LABEL) \
		--label "org.opencontainers.image.revision=$(COMMIT)" \
		--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
		--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
	        -f images/promenade/Dockerfile.${DISTRO} \
                $(_BASE_IMAGE_ARG) \
		--build-arg http_proxy=$(PROXY) \
		--build-arg https_proxy=$(PROXY) \
		--build-arg HTTP_PROXY=$(PROXY) \
		--build-arg HTTPS_PROXY=$(PROXY) \
		--build-arg no_proxy=$(NO_PROXY) \
		--build-arg NO_PROXY=$(NO_PROXY) .
else
	docker build --network host -t $(IMAGE) --label $(LABEL) \
		--label "org.opencontainers.image.revision=$(COMMIT)" \
		--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
		--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
	        -f images/promenade/Dockerfile.${DISTRO} \
		$(_BASE_IMAGE_ARG) .
endif
ifeq ($(PUSH_IMAGE), true)
	docker push $(IMAGE)
endif


helm-toolkit: helm-install
	./tools/helm_tk.sh $(HELM)

clean:
	rm -rf doc/build
	rm -f charts/*.tgz
	rm -f charts/*/requirements.lock
	rm -rf charts/*/charts
	rm -rf .tox

# Install helm binary
helm-install:
	tools/helm_install.sh $(HELM)

.PHONY: $(CHARTS) all build_promenade charts check-docker clean docs \
  dry-run dry-run-% external-deps gate-lint gate-lint-deps helm-init \
  helm-init-% helm-install helm-lint helm-lint-% helm-toolkit images \
  lint tests tests-pep8 tests-security tests-unit
