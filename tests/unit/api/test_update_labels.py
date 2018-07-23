# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import falcon
import json
import pytest

from falcon import testing
from promenade import promenade
from promenade.utils.success_message import SuccessMessage
from unittest import mock


@pytest.fixture()
def client():
    return testing.TestClient(promenade.start_promenade(disable='keystone'))


@pytest.fixture()
def req_header():
    return {
        'Content-Type': 'application/json',
        'X-IDENTITY-STATUS': 'Confirmed',
        'X-USER-NAME': 'Test',
        'X-ROLES': 'admin'
    }


@pytest.fixture()
def req_body():
    return json.dumps({
        "label-a": "value1",
        "label-c": "value4",
        "label-d": "value99"
    })


@mock.patch('promenade.kubeclient.KubeClient.update_node_labels')
@mock.patch('promenade.kubeclient.KubeClient.__init__')
def test_node_labels_pass(mock_kubeclient, mock_update_node_labels, client,
                          req_header, req_body):
    """
    Function to test node labels pass test case

    Args:
        mock_kubeclient: mock KubeClient object
        mock_update_node_labels: mock update_node_labels object
        client: Promenode APIs test client
        req_header: API request header
        req_body: API request body
    """
    mock_kubeclient.return_value = None
    mock_update_node_labels.return_value = _mock_update_node_labels()
    response = client.simulate_put(
        '/api/v1.0/node-labels/ubuntubox', headers=req_header, body=req_body)
    assert response.status == falcon.HTTP_200
    assert response.json["status"] == "Success"


def test_node_labels_missing_inputs(client, req_header, req_body):
    """
    Function to test node labels missing inputs

    Args:
        client: Promenode APIs test client
        req_header: API request header
        req_body: API request body
    """
    response = client.simulate_post(
        '/api/v1.0/node-labels', headers=req_header, body=req_body)
    assert response.status == falcon.HTTP_404


def _mock_update_node_labels():
    """Mock update_node_labels function"""
    resp_body_succ = SuccessMessage('Update node labels')
    return resp_body_succ.get_output_json()
