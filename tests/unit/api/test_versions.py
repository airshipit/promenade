import falcon
from falcon import testing
import pytest

from promenade.control.api import VersionsResource
from promenade.promenade import promenade


@pytest.fixture()
def client():
    return testing.TestClient(promenade)

def test_get_versions(client):
    response = client.simulate_get('/versions')
    assert response.status == falcon.HTTP_200
    body = response.content.decode('utf-8')
    assert '"path": "/api/v1.0"' in body
    assert '"status": "stable"' in body
