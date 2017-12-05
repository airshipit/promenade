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

from promenade.control.base import BaseResource
from promenade.builder import Builder
from promenade.config import Configuration
from promenade import logging
from promenade import policy
import falcon
import kubernetes
import random

LOG = logging.getLogger(__name__)


class JoinScriptsResource(BaseResource):
    """
    Lists the versions supported by this API
    """

    @policy.ApiEnforcer('kubernetes_provisioner:get_join_scripts')
    def on_get(self, req, resp):
        design_ref = req.get_param('design_ref', required=True)
        ip = req.get_param('ip', required=True)
        hostname = req.get_param('hostname', required=True)

        dynamic_labels = _get_param_list(req, 'labels.dynamic')
        static_labels = _get_param_list(req, 'labels.static')

        join_ip = _get_join_ip()

        config = Configuration.from_design_ref(design_ref)
        node_document = {
            'schema': 'promenade/KubernetesNode/v1',
            'metadata': {
                'name': hostname,
                'schema': 'metadata/Document/v1',
                'layeringDefinition': {
                    'abstract': False,
                    'layer': 'site'
                },
            },
            'data': {
                'hostname': hostname,
                'ip': ip,
                'join_ip': join_ip,
                'labels': {
                    'dynamic': dynamic_labels,
                    'static': static_labels,
                },
            },
        }
        config.append(node_document)

        builder = Builder(config)
        script = builder.build_node_script(hostname)

        resp.body = script
        resp.content_type = 'text/x-shellscript'
        resp.status = falcon.HTTP_200


def _get_join_ip():
    # TODO(mark-burnett): Handle errors
    kubernetes.config.load_incluster_config()
    client = kubernetes.client.CoreV1Api()
    response = client.list_node(label_selector='kubernetes-apiserver=enabled')

    # Ignore bandit false positive: B311:blacklist
    # The choice of which master to join to is a load-balancing concern, not a
    # security concern.
    return random.choice(list(map(_extract_ip, response.items)))  # nosec


def _extract_ip(item):
    for address in item.status.addresses:
        if address.type == 'InternalIP':
            return address.address


def _get_param_list(req, name):
    values = req.get_param_as_list(name)
    if values:
        return values
    else:
        return []
