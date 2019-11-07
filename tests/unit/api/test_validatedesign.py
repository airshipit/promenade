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

from falcon import testing
from promenade import promenade
from promenade.control import health_api
from unittest import mock
import copy
import falcon
import json
import pytest


@pytest.fixture()
def client():
    return testing.TestClient(promenade.start_promenade(disable='keystone'))


@pytest.fixture()
def std_headers():
    return {
        'Content-Type': 'application/json',
        'X-IDENTITY-STATUS': 'Confirmed',
        'X-USER-NAME': 'Test',
        'X-ROLES': 'admin'
    }


@pytest.fixture()
def std_body():
    return json.dumps({
        'rel': 'design',
        'href': 'http://localhost:9999',
        'type': 'application/x-yaml',
    })


def test_post_validatedesign_empty_docs(client, std_body, std_headers):
    with mock.patch('promenade.design_ref.get_documents') as gd:
        gd.return_value = ([], False)
        response = client.simulate_post(
            '/api/v1.0/validatedesign', headers=std_headers, body=std_body)
    assert response.status == falcon.HTTP_400
    assert response.json['details']['errorCount'] == 5


VALID_DOCS = [
    {
        'data': {
            'config': {
                'insecure-registries': ['registry:5000'],
                'live-restore': True,
                'max-concurrent-downloads': 10,
                'oom-score-adjust': -999,
                'storage-driver': 'overlay2'
            }
        },
        'metadata': {
            'layeringDefinition': {
                'abstract': False,
                'layer': 'site'
            },
            'name': 'docker',
            'schema': 'metadata/Document/v1',
            'storagePolicy': 'cleartext'
        },
        'schema': 'promenade/Docker/v1'
    },
    {
        'data': {
            'apiserver': {
                'command_prefix': [
                    '/apiserver', '--authorization-mode=Node,RBAC',
                    '--admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,ResourceQuota,DefaultTolerationSeconds',
                    '--service-cluster-ip-range=10.96.0.0/16',
                    '--endpoint-reconciler-type=lease'
                ]
            },
            'armada': {
                'target_manifest': 'cluster-bootstrap'
            },
            'files': [{
                'content':
                '# placeholder for triggering calico etcd bootstrapping',
                'mode':
                420,
                'path':
                '/var/lib/anchor/calico-etcd-bootstrap'
            }],
            'hostname':
            'n0',
            'images': {
                'armada': 'quay.io/airshipit/armada:master-ubuntu_xenial',
                'helm': {
                    'tiller': 'gcr.io/kubernetes-helm/tiller:v2.14.0'
                },
                'kubernetes': {
                    'apiserver':
                    'gcr.io/google_containers/hyperkube-amd64:v1.11.6',
                    'controller-manager':
                    'gcr.io/google_containers/hyperkube-amd64:v1.11.6',
                    'etcd':
                    'quay.io/coreos/etcd:v3.4.2',
                    'scheduler':
                    'gcr.io/google_containers/hyperkube-amd64:v1.11.6'
                }
            },
            'ip':
            '192.168.77.10',
            'labels': {
                'dynamic': [
                    'calico-etcd=enabled', 'coredns=enabled',
                    'kubernetes-apiserver=enabled',
                    'kubernetes-controller-manager=enabled',
                    'kubernetes-etcd=enabled', 'kubernetes-scheduler=enabled',
                    'promenade-genesis=enabled', 'ucp-control-plane=enabled'
                ]
            }
        },
        'metadata': {
            'layeringDefinition': {
                'abstract': False,
                'layer': 'site'
            },
            'name': 'genesis',
            'schema': 'metadata/Document/v1'
        },
        'schema': 'promenade/Genesis/v1'
    },
    {
        'data': {
            'files':
            [{
                'mode':
                365,
                'path':
                '/opt/kubernetes/bin/kubelet',
                'tar_path':
                'kubernetes/node/bin/kubelet',
                'tar_url':
                'https://dl.k8s.io/v1.11.6/kubernetes-node-linux-amd64.tar.gz'
            },
             {
                 'content':
                 '/var/lib/docker/containers/*/*-json.log\n{\n    compress\n    copytruncate\n    create 0644 root root\n    daily\n    dateext\n    dateformat -%Y%m%d-%s\n    maxsize 10M\n    missingok\n    notifempty\n    su root root\n    rotate 1\n}',
                 'mode':
                 292,
                 'path':
                 '/etc/logrotate.d/json-logrotate'
             }],
            'images': {
                'haproxy': 'haproxy:1.8.3',
                'helm': {
                    'helm': 'lachlanevenson/k8s-helm:v2.14.0'
                },
                'kubernetes': {
                    'kubectl':
                    'gcr.io/google_containers/hyperkube-amd64:v1.11.6'
                }
            },
            'packages': {
                'additional': ['curl', 'jq'],
                'keys': [
                    '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nmQINBFWln24BEADrBl5p99uKh8+rpvqJ48u4eTtjeXAWbslJotmC/CakbNSqOb9o\nddfzRvGVeJVERt/Q/mlvEqgnyTQy+e6oEYN2Y2kqXceUhXagThnqCoxcEJ3+KM4R\nmYdoe/BJ/J/6rHOjq7Omk24z2qB3RU1uAv57iY5VGw5p45uZB4C4pNNsBJXoCvPn\nTGAs/7IrekFZDDgVraPx/hdiwopQ8NltSfZCyu/jPpWFK28TR8yfVlzYFwibj5WK\ndHM7ZTqlA1tHIG+agyPf3Rae0jPMsHR6q+arXVwMccyOi+ULU0z8mHUJ3iEMIrpT\nX+80KaN/ZjibfsBOCjcfiJSB/acn4nxQQgNZigna32velafhQivsNREFeJpzENiG\nHOoyC6qVeOgKrRiKxzymj0FIMLru/iFF5pSWcBQB7PYlt8J0G80lAcPr6VCiN+4c\nNKv03SdvA69dCOj79PuO9IIvQsJXsSq96HB+TeEmmL+xSdpGtGdCJHHM1fDeCqkZ\nhT+RtBGQL2SEdWjxbF43oQopocT8cHvyX6Zaltn0svoGs+wX3Z/H6/8P5anog43U\n65c0A+64Jj00rNDr8j31izhtQMRo892kGeQAaaxg4Pz6HnS7hRC+cOMHUU4HA7iM\nzHrouAdYeTZeZEQOA7SxtCME9ZnGwe2grxPXh/U/80WJGkzLFNcTKdv+rwARAQAB\ntDdEb2NrZXIgUmVsZWFzZSBUb29sIChyZWxlYXNlZG9ja2VyKSA8ZG9ja2VyQGRv\nY2tlci5jb20+iQI4BBMBAgAiBQJVpZ9uAhsvBgsJCAcDAgYVCAIJCgsEFgIDAQIe\nAQIXgAAKCRD3YiFXLFJgnbRfEAC9Uai7Rv20QIDlDogRzd+Vebg4ahyoUdj0CH+n\nAk40RIoq6G26u1e+sdgjpCa8jF6vrx+smpgd1HeJdmpahUX0XN3X9f9qU9oj9A4I\n1WDalRWJh+tP5WNv2ySy6AwcP9QnjuBMRTnTK27pk1sEMg9oJHK5p+ts8hlSC4Sl\nuyMKH5NMVy9c+A9yqq9NF6M6d6/ehKfBFFLG9BX+XLBATvf1ZemGVHQusCQebTGv\n0C0V9yqtdPdRWVIEhHxyNHATaVYOafTj/EF0lDxLl6zDT6trRV5n9F1VCEh4Aal8\nL5MxVPcIZVO7NHT2EkQgn8CvWjV3oKl2GopZF8V4XdJRl90U/WDv/6cmfI08GkzD\nYBHhS8ULWRFwGKobsSTyIvnbk4NtKdnTGyTJCQ8+6i52s+C54PiNgfj2ieNn6oOR\n7d+bNCcG1CdOYY+ZXVOcsjl73UYvtJrO0Rl/NpYERkZ5d/tzw4jZ6FCXgggA/Zxc\njk6Y1ZvIm8Mt8wLRFH9Nww+FVsCtaCXJLP8DlJLASMD9rl5QS9Ku3u7ZNrr5HWXP\nHXITX660jglyshch6CWeiUATqjIAzkEQom/kEnOrvJAtkypRJ59vYQOedZ1sFVEL\nMXg2UCkD/FwojfnVtjzYaTCeGwFQeqzHmM241iuOmBYPeyTY5veF49aBJA1gEJOQ\nTvBR8Q==\n=Fm3p\n-----END PGP PUBLIC KEY BLOCK-----'
                ],
                'repositories':
                ['deb http://apt.dockerproject.org/repo ubuntu-xenial main'],
                'required': {
                    'docker': 'docker-engine=1.13.1-0~ubuntu-xenial',
                    'socat': 'socat=1.7.3.1-1'
                }
            },
            'validation': {
                'pod_logs': {
                    'image': 'busybox:1.28.3'
                }
            }
        },
        'metadata': {
            'layeringDefinition': {
                'abstract': False,
                'layer': 'site'
            },
            'name': 'host-system',
            'schema': 'metadata/Document/v1'
        },
        'schema': 'promenade/HostSystem/v1'
    },
    {
        'data': {
            'arguments': [
                '--cni-bin-dir=/opt/cni/bin', '--cni-conf-dir=/etc/cni/net.d',
                '--network-plugin=cni', '--v=5'
            ],
            'images': {
                'pause': 'gcr.io/google_containers/pause-amd64:3.0'
            },
            'config_file_overrides': {
                'evictionMaxPodGracePeriod': -1,
                'nodeStatusUpdateFrequency': '5s',
                'serializeImagePulls': 'false'
            }
        },
        'metadata': {
            'layeringDefinition': {
                'abstract': False,
                'layer': 'site'
            },
            'name': 'kubelet',
            'schema': 'metadata/Document/v1',
            'storagePolicy': 'cleartext'
        },
        'schema': 'promenade/Kubelet/v1'
    },
    {
        'data': {
            'dns': {
                'bootstrap_validation_checks': [
                    'calico-etcd.kube-system.svc.cluster.local', 'google.com',
                    'kubernetes-etcd.kube-system.svc.cluster.local',
                    'kubernetes.default.svc.cluster.local'
                ],
                'cluster_domain':
                'cluster.local',
                'service_ip':
                '10.96.0.10',
                'upstream_servers': ['8.8.8.8', '8.8.4.4']
            },
            'etcd': {
                'container_port': 2379,
                'haproxy_port': 2378
            },
            'hosts_entries': [{
                'ip': '192.168.77.1',
                'names': ['registry']
            }],
            'kubernetes': {
                'apiserver_port': 6443,
                'haproxy_port': 6553,
                'pod_cidr': '10.97.0.0/16',
                'service_cidr': '10.96.0.0/16',
                'service_ip': '10.96.0.1'
            }
        },
        'metadata': {
            'layeringDefinition': {
                'abstract': False,
                'layer': 'site'
            },
            'name': 'kubernetes-network',
            'schema': 'metadata/Document/v1',
            'storagePolicy': 'cleartext'
        },
        'schema': 'promenade/KubernetesNetwork/v1'
    },
]


def test_post_validatedesign_valid_docs(client, std_body, std_headers):
    with mock.patch('promenade.design_ref.get_documents') as gd:
        gd.return_value = (VALID_DOCS, False)
        response = client.simulate_post(
            '/api/v1.0/validatedesign', headers=std_headers, body=std_body)
    assert response.status == falcon.HTTP_200
    assert response.json['details']['errorCount'] == 0
