# Copyright 2017 AT&T Intellectual Property.  All other rights reserved.
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
from falcon import testing
import pytest

from promenade.control.api import VersionsResource
from promenade import promenade


@pytest.fixture()
def client():
    return testing.TestClient(promenade.start_promenade(disable='keystone'))


def test_get_versions(client):
    response = client.simulate_get('/versions')
    assert response.status == falcon.HTTP_200
    assert response.json == {'v1.0': {'path': '/api/v1.0', 'status': 'stable'}}
