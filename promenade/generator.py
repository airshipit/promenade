from . import config, logging, pki, renderer
import os

__all__ = ['Generator']


LOG = logging.getLogger(__name__)


class Generator:
    @classmethod
    def from_config(cls, *, config_path):
        return cls(input_config=(config.load(config_path)))

    def __init__(self, *, input_config):
        self.input_config = input_config

        self.validate()

    def validate(self):
        required_kinds = ['Cluster', 'Network', 'Versions']
        for required_kind in required_kinds:
            try:
                self.input_config[required_kind]
            except KeyError:
                LOG.error('Generator requires one "%s" document to function.',
                          required_kind)
                raise

        assert self.input_config['Cluster'].metadata['name'] \
                == self.input_config['Network'].metadata['cluster']

    def generate_additional_scripts(self, output_dir):
        r = renderer.Renderer(config=self.input_config,
                              target_dir=output_dir)
        r.render_generate_files()

    def generate_all(self, output_dir):
        self.generate_additional_scripts(output_dir)

        cluster = self.input_config['Cluster']
        network = self.input_config['Network']
        versions = self.input_config['Versions']

        cluster_name = cluster.metadata['name']
        LOG.info('Generating configuration for cluster "%s"', cluster_name)
        masters = self.construct_masters(cluster_name)

        LOG.info('Generating common PKI for cluster "%s"', cluster_name)
        keys = pki.PKI(cluster_name)
        cluster_ca, cluster_ca_key = keys.generate_ca(
                ca_name='cluster',
                cert_target='all',
                key_target='masters')
        etcd_client_ca, etcd_client_ca_key = keys.generate_ca(
                ca_name='etcd-client',
                cert_target='masters',
                key_target='masters')
        etcd_peer_ca, etcd_peer_ca_key = keys.generate_ca(
                ca_name='etcd-peer',
                cert_target='masters',
                key_target='masters')
        calico_etcd_client_ca, calico_etcd_client_ca_key = keys.generate_ca(
                ca_name='calico-etcd-client',
                cert_target='masters',
                key_target='masters')
        calico_etcd_peer_ca, calico_etcd_peer_ca_key = keys.generate_ca(
                ca_name='calico-etcd-peer',
                cert_target='masters',
                key_target='masters')

        admin_cert, admin_cert_key = keys.generate_certificate(
            name='admin',
            ca_name='cluster',
            groups=['system:masters'],
            target='masters',
        )

        sa_pub, sa_priv = keys.generate_keypair(
            name='service-account',
            target='masters',
        )

        config.Configuration([
            admin_cert,
            admin_cert_key,
            calico_etcd_client_ca,
            calico_etcd_client_ca_key,
            calico_etcd_peer_ca,
            calico_etcd_peer_ca_key,
            cluster_ca,
            cluster_ca_key,
            etcd_client_ca,
            etcd_client_ca_key,
            etcd_peer_ca,
            etcd_peer_ca_key,
            sa_priv,
            sa_pub,
        ]).write(os.path.join(output_dir, 'admin-bundle.yaml'))

        complete_configuration = [
            admin_cert,
            admin_cert_key,
            calico_etcd_client_ca,
            calico_etcd_client_ca_key,
            calico_etcd_peer_ca,
            calico_etcd_peer_ca_key,
            cluster_ca,
            cluster_ca_key,
            etcd_client_ca,
            etcd_client_ca_key,
            etcd_peer_ca,
            etcd_peer_ca_key,
            masters,
            network,
            sa_priv,
            sa_pub,
            versions,
        ]

        for hostname, data in cluster['nodes'].items():
            if 'genesis' in data.get('roles', []):
                genesis_hostname = hostname
                break

        for hostname, data in cluster['nodes'].items():
            LOG.debug('Generating configuration & PKI for hostname=%s',
                      hostname)
            node = _construct_node_config(cluster_name, hostname, data)

            kubelet_cert, kubelet_cert_key = keys.generate_certificate(
                    alias='kubelet',
                    name='system:node:%s' % hostname,
                    ca_name='cluster',
                    groups=['system:nodes'],
                    hosts=[
                        hostname,
                        data['ip'],
                    ],
                    target=hostname)

            proxy_cert, proxy_cert_key = keys.generate_certificate(
                    alias='proxy',
                    config_name='system:kube-proxy:%s' % hostname,
                    name='system:kube-proxy',
                    ca_name='cluster',
                    hosts=[
                        hostname,
                        data['ip'],
                    ],
                    target=hostname)

            complete_configuration.extend([
                kubelet_cert,
                kubelet_cert_key,
                node,
                proxy_cert,
                proxy_cert_key,
            ])

            common_documents = [
                cluster_ca,
                kubelet_cert,
                kubelet_cert_key,
                masters,
                network,
                node,
                proxy_cert,
                proxy_cert_key,
                versions,
            ]
            role_specific_documents = []

            if 'master' in data.get('roles', []):
                role_specific_documents.extend([
                    admin_cert,
                    admin_cert_key,
                    calico_etcd_client_ca,
                    calico_etcd_peer_ca,
                    cluster_ca_key,
                    etcd_client_ca,
                    etcd_peer_ca,
                    sa_priv,
                    sa_pub,
                ])
                if 'genesis' not in data.get('roles', []):
                    etcd_config = _master_etcd_config(
                            cluster_name, genesis_hostname, hostname, masters)
                    calico_etcd_config = _master_calico_etcd_config(
                            cluster_name, genesis_hostname, hostname, masters)
                    complete_configuration.append(etcd_config)
                    complete_configuration.append(calico_etcd_config)
                    role_specific_documents.append(etcd_config)
                    role_specific_documents.append(calico_etcd_config)
                master_documents = _master_config(hostname, data,
                                                  masters, network, keys)
                complete_configuration.extend(master_documents)
                role_specific_documents.extend(master_documents)

            if 'genesis' in data.get('roles', []):
                role_specific_documents.extend(_genesis_config(hostname, data,
                                                               masters, network, keys))
                role_specific_documents.append(_genesis_etcd_config(cluster_name, hostname))
                role_specific_documents.append(_genesis_calico_etcd_config(cluster_name, hostname))
                node.data['spec']['is_genesis'] = True

            c = config.Configuration(common_documents + role_specific_documents)
            c.write(os.path.join(output_dir, hostname + '.yaml'))

        config.Configuration(complete_configuration).write(
                os.path.join(output_dir, 'complete-bundle.yaml'))

    def construct_masters(self, cluster_name):
        masters = []
        for hostname, data in self.input_config['Cluster']['nodes'].items():
            if 'master' in data.get('roles', []) or 'genesis' in data.get('roles', []):
                masters.append({'hostname': hostname, 'ip': data['ip']})

        return config.Document({
            'apiVersion': 'promenade/v1',
            'kind': 'Masters',
            'metadata': {
                'cluster': cluster_name,
                'name': cluster_name,
                'target': 'all',
            },
            'spec': {
                'nodes': masters,
            },
        })


def _master_etcd_config(cluster_name, genesis_hostname, hostname, masters):
    initial_cluster = ['%s=https://%s:2380' % (m['hostname'],
                                               m['hostname'])
                       for m in masters['nodes']]
    initial_cluster.extend([
        'auxiliary-etcd-0=https://%s:12380' % genesis_hostname,
        'auxiliary-etcd-1=https://%s:22380' % genesis_hostname,
    ])
    return _etcd_config(cluster_name, alias='kube-etcd',
                        name='master-kube-etcd:%s' % hostname,
                        target=hostname,
                        initial_cluster=initial_cluster,
                        initial_cluster_state='existing')


def _master_calico_etcd_config(cluster_name, genesis_hostname, hostname, masters):
    initial_cluster = ['%s=https://%s:6667' % (m['hostname'],
                                               m['hostname'])
                       for m in masters['nodes']]
    initial_cluster.extend([
        'auxiliary-calico-etcd-0=https://%s:16667' % genesis_hostname,
        'auxiliary-calico-etcd-1=https://%s:26667' % genesis_hostname,
    ])
    return _etcd_config(cluster_name, alias='calico-etcd',
                        name='master-calico-etcd:%s' % hostname,
                        target=hostname,
                        initial_cluster=initial_cluster,
                        initial_cluster_state='existing')


def _genesis_etcd_config(cluster_name, hostname):
    initial_cluster = [
        '%s=https://%s:2380' % (hostname, hostname),
        'auxiliary-etcd-0=https://%s:12380' % hostname,
        'auxiliary-etcd-1=https://%s:22380' % hostname,
    ]
    return _etcd_config(cluster_name, alias='kube-etcd',
                        name='master-kube-etcd:%s' % hostname,
                        target=hostname,
                        initial_cluster=initial_cluster,
                        initial_cluster_state='new')


def _genesis_calico_etcd_config(cluster_name, hostname):
    initial_cluster = [
        '%s=https://%s:6667' % (hostname, hostname),
        'auxiliary-calico-etcd-0=https://%s:16667' % hostname,
        'auxiliary-calico-etcd-1=https://%s:26667' % hostname,
    ]
    return _etcd_config(cluster_name, alias='calico-etcd',
                        name='master-calico-etcd:%s' % hostname,
                        target=hostname,
                        initial_cluster=initial_cluster,
                        initial_cluster_state='new')


def _etcd_config(cluster_name, *, alias, name, target,
                 initial_cluster, initial_cluster_state):
    return config.Document({
        'apiVersion': 'promenade/v1',
        'kind': 'Etcd',
        'metadata': {
            'cluster': cluster_name,
            'alias': alias,
            'name': name,
            'target': target,
        },
        'spec': {
            'initial_cluster': initial_cluster,
            'initial_cluster_state': initial_cluster_state,
        },
    })


def _master_config(hostname, host_data, masters, network, keys):
    kube_domains = [
        'kubernetes',
        'kubernetes.default',
        'kubernetes.default.svc',
        'kubernetes.default.svc.cluster.local',
        '127.0.0.1',
    ]
    calico_domains = [
        'calico-etcd',
        'calico-etcd.kube-system',
        'calico-etcd.kube-system.svc',
        'calico-etcd.kube-system.svc.cluster.local',
        network['calico_etcd_service_ip'],
    ]

    docs = []

    docs.extend(keys.generate_certificate(
        alias='etcd-client',
        name='etcd:client:%s' % hostname,
        ca_name='etcd-client',
        hosts=kube_domains + calico_domains + [hostname, host_data['ip']],
        target=hostname,
    ))
    docs.extend(keys.generate_certificate(
        alias='etcd-apiserver-client',
        name='etcd:client:apiserver:%s' % hostname,
        ca_name='etcd-client',
        hosts=[hostname, host_data['ip']],
        target=hostname,
    ))

    docs.extend(keys.generate_certificate(
        alias='etcd-peer',
        name='etcd:peer:%s' % hostname,
        ca_name='etcd-peer',
        hosts=kube_domains + [hostname, host_data['ip']],
        target=hostname,
    ))

    docs.extend(keys.generate_certificate(
        alias='calico-etcd-client',
        name='calico-etcd:client:%s' % hostname,
        ca_name='calico-etcd-client',
        hosts=kube_domains + calico_domains + [hostname, host_data['ip']],
        target=hostname,
    ))

    docs.extend(keys.generate_certificate(
        alias='calico-etcd-peer',
        name='calico-etcd:peer:%s' % hostname,
        ca_name='calico-etcd-peer',
        hosts=kube_domains + [hostname, host_data['ip']],
        target=hostname,
    ))

    docs.extend(keys.generate_certificate(
        alias='apiserver',
        name='apiserver:%s' % hostname,
        ca_name='cluster',
        hosts=kube_domains + [
            network['kube_service_ip'],
            hostname,
            host_data['ip'],
        ],
        target=hostname,
    ))

    docs.extend(keys.generate_certificate(
        alias='controller-manager',
        config_name='system:kube-controller-manager:%s' % hostname,
        name='system:kube-controller-manager',
        ca_name='cluster',
        hosts=[
            hostname,
            host_data['ip'],
        ],
        target=hostname,
    ))

    docs.extend(keys.generate_certificate(
        alias='scheduler',
        config_name='system:kube-scheduler:%s' % hostname,
        name='system:kube-scheduler',
        ca_name='cluster',
        hosts=[
            hostname,
            host_data['ip'],
        ],
        target=hostname,
    ))

    return docs


def _genesis_config(hostname, host_data, masters, network, keys):
    docs = []

    for i in range(2):
        docs.extend(keys.generate_certificate(
            name='auxiliary-etcd-%d-client' % i,
            ca_name='etcd-client',
            hosts=[hostname, host_data['ip']],
            target=hostname,
        ))

        docs.extend(keys.generate_certificate(
            name='auxiliary-etcd-%d-peer' % i,
            ca_name='etcd-peer',
            hosts=[hostname, host_data['ip']],
            target=hostname,
        ))

        docs.extend(keys.generate_certificate(
            name='auxiliary-calico-etcd-%d-client' % i,
            ca_name='calico-etcd-client',
            hosts=[hostname, host_data['ip']],
            target=hostname,
        ))

        docs.extend(keys.generate_certificate(
            name='auxiliary-calico-etcd-%d-peer' % i,
            ca_name='calico-etcd-peer',
            hosts=[hostname, host_data['ip']],
            target=hostname,
        ))

    docs.extend(keys.generate_certificate(
        alias='calico-etcd-node-client',
        name='calico-etcd:node',
        ca_name='calico-etcd-client',
        target=hostname,
    ))

    return docs


def _construct_node_config(cluster_name, hostname, data):
    spec = {
        'hostname': hostname,
        'ip': data['ip'],
        'labels': _labels(data.get('roles', []), data.get('additional_labels', [])),
        'templates': _templates(data.get('roles', [])),
    }

    return config.Document({
        'apiVersion': 'promenade/v1',
        'kind': 'Node',
        'metadata': {
            'cluster': cluster_name,
            'name': hostname,
            'target': hostname,
        },
        'spec': spec,
    })


ROLE_LABELS = {
    'genesis': [
        'promenade=genesis',
    ],
    'master': [
        'node-role.kubernetes.io/master=',
    ],
}


def _labels(roles, additional_labels):
    result = set()
    for role in roles:
        result.update(ROLE_LABELS.get(role, []))
    result.update(additional_labels)
    return sorted(result)


def _templates(roles):
    return ['common'] + roles
