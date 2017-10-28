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

HELM ?= helm
HELM_PIDFILE ?= $(abspath ./.helm-pid)
TMP_DIR ?= $(abspath ./tmp)

CHARTS := $(patsubst %/.,%,$(wildcard charts/*/.))

.PHONY: all
all: charts

.PHONY: charts
charts: $(CHARTS)
	@echo Done building charts.

.PHONY: $(CHARTS)
$(CHARTS): helm-serve
	@echo $@
	if [ -s $@/requirements.yaml ]; then $(HELM) dep up $@; fi
	$(HELM) lint $@
	$(HELM) template $@
	$(HELM) package -d charts $@

.PHONY: helm-serve
helm-serve:
	./tools/helm_tk.sh $(HELM) $(HELM_PIDFILE) $(TMP_DIR)

.PHONY: clean
clean:
	rm -f charts/*.tgz
	rm -f charts/*/requirements.lock
	rm -rf charts/*/charts
