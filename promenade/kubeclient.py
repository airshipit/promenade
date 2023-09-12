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
import kubernetes
from kubernetes.client.rest import ApiException
from urllib3.exceptions import MaxRetryError

from promenade import logging
from promenade.exceptions import KubernetesApiError
from promenade.exceptions import KubernetesConfigException
from promenade.exceptions import NodeNotFoundException
from promenade.utils.success_message import SuccessMessage

LOG = logging.getLogger(__name__)


class KubeClient(object):
    """
    Class for Kubernetes APIs client
    """

    def __init__(self):
        """ Set Kubernetes APIs connection """
        try:
            LOG.info('Loading in-cluster Kubernetes configuration.')
            kubernetes.config.load_incluster_config()
        except kubernetes.config.config_exception.ConfigException:
            LOG.debug('Failed to load in-cluster configuration')
            try:
                LOG.info('Loading out-of-cluster Kubernetes configuration.')
                kubernetes.config.load_kube_config()
            except FileNotFoundError:
                LOG.exception(
                    'FileNotFoundError: Failed to load Kubernetes config file.'
                )
                raise KubernetesConfigException
        self.client = kubernetes.client.CoreV1Api()

    def update_node_labels(self, node_name, input_labels):
        """
        Updating node labels

        Args:
            node_name(str): node for which updating labels
            input_labels(dict): input labels dict
        Returns:
            SuccessMessage(dict): API success response
        """
        resp_body_succ = SuccessMessage('Update node labels', falcon.HTTP_200)

        try:
            existing_labels = self.get_node_labels(node_name)
            update_labels = _get_update_labels(existing_labels, input_labels)
            # If there is a change
            if bool(update_labels):
                body = {"metadata": {"labels": update_labels}}
                self.client.patch_node(node_name, body)
            return resp_body_succ.get_output_json()
        except (ApiException, MaxRetryError) as e:
            LOG.exception("An exception occurred during node labels update: " +
                          str(e))
            raise KubernetesApiError

    def get_node_labels(self, node_name):
        """
        Get existing registered node labels

        Args:
            node_name(str): node of which getting labels
        Returns:
            dict: labels dict
        """
        try:
            response = self.client.read_node(node_name)
            if response is not None:
                return response.metadata.labels
            else:
                return {}
        except (ApiException, MaxRetryError) as e:
            LOG.exception("An exception occurred in fetching node labels: " +
                          str(e))
            if hasattr(e, 'status') and str(e.status) == "404":
                raise NodeNotFoundException
            else:
                raise KubernetesApiError


def _get_update_labels(existing_labels, input_labels):
    """
    Helper function to add new labels, delete labels, override
    existing labels

    Args:
        existing_labels(dict): Existing node labels
        input_labels(dict): Input/Req. labels
    Returns:
        update_labels(dict): Node labels to be updated
        or
        input_labels(dict): Node labels to be updated
    """
    update_labels = {}

    # no existing labels found
    if not existing_labels:
        # filter delete label request since there is no labels set on a node
        update_labels.update(
            {k: v
             for k, v in input_labels.items() if v is not None})
        return update_labels

    # new labels or overriding labels
    update_labels.update({
        k: v
        for k, v in input_labels.items()
        if k not in existing_labels or v != existing_labels[k]
    })

    # deleted labels
    update_labels.update({
        k: None
        for k in existing_labels.keys()
        if k not in input_labels and "kubernetes.io" not in k
    })
    return update_labels
