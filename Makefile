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
COMMIT            ?= commit-id
PYTHON            = python3
CHARTS            := $(patsubst charts/%/.,%,$(wildcard charts/*/.))
IMAGE             := ${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}
PYTHON_BASE_IMAGE ?= python:3.6

HELM_PIDFILE ?= $(abspath ./.helm-pid)

CHARTS := $(patsubst charts/%/.,%,$(wildcard charts/*/.))

.PHONY: all
all: charts lint

.PHONY: tests
tests: gate-lint
	tox

.PHONY: tests-security
tests-security:
	tox -e bandit

.PHONY: docs
docs:
	tox -e docs

.PHONY: tests-unit
tests-unit:
	tox -e py35

.PHONY: tests-pep8
tests-pep8:
	tox -e pep8

chartbanner:
	@echo Building charts: $(CHARTS)

.PHONY: charts
charts: $(CHARTS)
	@echo Done building charts.

.PHONY: helm-init
helm-init: $(addprefix helm-init-,$(CHARTS))

.PHONY: helm-init-%
helm-init-%: helm-serve
	@echo Initializing chart $*
	cd charts;if [ -s $*/requirements.yaml ]; then echo "Initializing $*";$(HELM) dep up $*; fi

.PHONY: lint
lint: helm-lint gate-lint

.PHONY: gate-lint
gate-lint: gate-lint-deps
	tox -e gate-lint

.PHONY: gate-lint-deps
gate-lint-deps:
	sudo apt-get install -y --no-install-recommends shellcheck

.PHONY: helm-lint
helm-lint: $(addprefix helm-lint-,$(CHARTS))

.PHONY: helm-lint-%
helm-lint-%: helm-install helm-init-%
	@echo Linting chart $*
	cd charts;$(HELM) lint $*

.PHONY: images
images: check-docker build_promenade

.PHONY: check-docker
check-docker:
	@if [ -z $$(which docker) ]; then \
		echo "Missing \`docker\` client which is required for development"; \
		exit 2; \
	fi

.PHONY: dry-run
dry-run: $(addprefix dry-run-,$(CHARTS))

.PHONY: dry-run-%
dry-run-%: helm-lint-%
	echo Running Dry-Run on chart $*
	cd charts;$(HELM) template --set pod.resources.enabled=true $*

.PHONY: $(CHARTS)
$(CHARTS): $(addprefix dry-run-,$(CHARTS)) chartbanner
	$(HELM) package -d charts charts/$@

.PHONY: build_promenade
build_promenade:
ifeq ($(USE_PROXY), true)
	docker build --network host -t $(IMAGE) \
		--label "org.opencontainers.image.revision=$(COMMIT)" \
		--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
		--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
		-f ./Dockerfile \
		--build-arg FROM=$(PYTHON_BASE_IMAGE) \
		--build-arg http_proxy=$(PROXY) \
		--build-arg https_proxy=$(PROXY) \
		--build-arg HTTP_PROXY=$(PROXY) \
		--build-arg HTTPS_PROXY=$(PROXY) \
		--build-arg no_proxy=$(NO_PROXY) \
		--build-arg NO_PROXY=$(NO_PROXY) .
else
	docker build --network host -t $(IMAGE) \
		--label "org.opencontainers.image.revision=$(COMMIT)" \
		--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
		--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
		-f ./Dockerfile \
		--build-arg FROM=$(PYTHON_BASE_IMAGE) .
endif
ifeq ($(PUSH_IMAGE), true)
	docker push $(IMAGE)
endif


.PHONY: helm-serve
helm-serve: helm-install
	./tools/helm_tk.sh $(HELM) $(HELM_PIDFILE)

.PHONY: clean
clean:
	rm -f charts/*.tgz
	rm -f charts/*/requirements.lock
	rm -rf charts/*/charts

# Install helm binary
.PHONY: helm-install
helm-install:
	tools/helm_install.sh $(HELM)
