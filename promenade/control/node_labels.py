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

import falcon

from promenade.control.base import BaseResource
from promenade.kubeclient import KubeClient
from promenade import exceptions
from promenade import logging
from promenade import policy

LOG = logging.getLogger(__name__)


class NodeLabelsResource(BaseResource):
    """Class for Node Labels Manage API"""

    @policy.ApiEnforcer('kubernetes_provisioner:update_node_labels')
    def on_put(self, req, resp, node_name=None):
        json_data = self.req_json(req)
        if node_name is None:
            LOG.error("Invalid format error: Missing input: node_name")
            raise exceptions.InvalidFormatError(
                description="Missing input: node_name")
        if json_data is None:
            LOG.error("Invalid format error: Missing input: labels dict")
            raise exceptions.InvalidFormatError(
                description="Missing input: labels dict")
        kubeclient = KubeClient()
        response = kubeclient.update_node_labels(node_name, json_data)

        resp.body = response
        resp.status = falcon.HTTP_200
