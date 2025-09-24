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

import falcon
import kubernetes

from promenade.control.base import BaseResource
from promenade.builder import Builder
from promenade.config import Configuration
from promenade import exceptions
from promenade import logging
from promenade import policy

LOG = logging.getLogger(__name__)

SENTINEL = object()


class JoinScriptsResource(BaseResource):
    """
    Lists the versions supported by this API
    """

    @policy.ApiEnforcer('kubernetes_provisioner:get_join_scripts')
    def on_get(self, req, resp):
        leave_kubectl = req.get_param_as_bool('leave_kubectl')
        design_ref = req.get_param('design_ref', required=True)
        # The required IP address to be used by Kubernetes itself
        ip = req.get_param('ip', required=True)
        # The optional IP address to configure as externally-routable
        external_ip = req.get_param('external_ip', default='127.0.0.1')
        hostname = req.get_param('hostname', required=True)
        # NOTE(sh8121att): Set a default here for backward compatability
        dns_domain = req.get_param('domain', default='local')

        dynamic_labels = _get_param_list(req, 'labels.dynamic')
        static_labels = _get_param_list(req, 'labels.static')

        join_ips = _get_join_ips()

        try:
            config = Configuration.from_design_ref(
                design_ref,
                allow_missing_substitutions=False,
                leave_kubectl=leave_kubectl)
        except exceptions.DeckhandException:
            LOG.exception('Caught Deckhand render error for configuration')
            raise

        if config.get_path('KubernetesNode:.', SENTINEL) != SENTINEL:
            raise exceptions.ExistingKubernetesNodeDocumentError(
                'Existing KubernetesNode documents found')

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
                'domain': dns_domain,
                'ip': ip,
                'external_ip': external_ip,
                'join_ips': join_ips,
                'labels': {
                    'dynamic': dynamic_labels,
                    'static': static_labels,
                },
            },
        }
        config.append(node_document)

        builder = Builder(config)
        script = builder.build_node_script(hostname)

        resp.text = script
        resp.content_type = 'text/x-shellscript'
        resp.status = falcon.HTTP_200


def _get_join_ips():
    # TODO(mark-burnett): Handle errors
    kubernetes.config.load_incluster_config()
    client = kubernetes.client.CoreV1Api()
    response = client.list_node(label_selector='kubernetes-apiserver=enabled')

    return list(map(_extract_ip, response.items))


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
