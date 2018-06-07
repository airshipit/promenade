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

BUILD_DIR := $(shell mktemp -d)
HELM := $(BUILD_DIR)/helm
HELM ?= helm
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

.PHONY: dry-run
dry-run: $(addprefix dry-run-,$(CHARTS))

.PHONY: dry-run-%
dry-run-%: helm-lint-%
	echo Running Dry-Run on chart $*
	cd charts;$(HELM) template --set pod.resources.enabled=true $*

.PHONY: $(CHARTS)
$(CHARTS): $(addprefix dry-run-,$(CHARTS)) chartbanner
	$(HELM) package -d charts charts/$@

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
