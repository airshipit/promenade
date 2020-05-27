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
                    'tiller': 'gcr.io/kubernetes-helm/tiller:v2.16.1'
                },
                'kubernetes': {
                    'apiserver':
                    'gcr.io/google_containers/hyperkube-amd64:v1.17.3',
                    'controller-manager':
                    'gcr.io/google_containers/hyperkube-amd64:v1.17.3',
                    'etcd':
                    'quay.io/coreos/etcd:v3.4.2',
                    'scheduler':
                    'gcr.io/google_containers/hyperkube-amd64:v1.17.3'
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
                'https://dl.k8s.io/v1.17.3/kubernetes-node-linux-amd64.tar.gz'
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
                    'gcr.io/google_containers/hyperkube-amd64:v1.17.3'
                }
            },
            'packages': {
                'additional': ['curl', 'jq'],
                'keys': [
                    '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n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\nYT90qFF93M3v01BbxP+EIY2/9tiIPbrd\n=0YYh\n-----END PGP PUBLIC KEY BLOCK-----'
                ],
                'repositories': [
                    'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'
                ],
                'required': {
                    'docker': 'docker-ce=5:19.03.8~3-0~ubuntu-bionic',
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
                'pause': 'gcr.io/google_containers/pause-amd64:3.1'
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
