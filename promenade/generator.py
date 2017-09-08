from . import logging, pki
import os
import yaml

__all__ = ['Generator']

LOG = logging.getLogger(__name__)


class Generator:
    def __init__(self, config, *, calico_etcd_service_ip):
        self.config = config
        self.calico_etcd_service_ip = calico_etcd_service_ip
        self.keys = pki.PKI()
        self.documents = []

    @property
    def cluster_domain(self):
        return self.config['KubernetesNetwork:dns.cluster_domain']

    def generate(self, output_dir):
        # Certificate Authorities
        self.gen('ca', 'kubernetes')
        self.gen('ca', 'kubernetes-etcd')
        self.gen('ca', 'kubernetes-etcd-peer')
        self.gen('ca', 'calico-etcd')
        self.gen('ca', 'calico-etcd-peer')

        # Certificates for Kubernetes API server
        self.gen(
            'certificate',
            'apiserver',
            ca='kubernetes',
            cn='apiserver',
            hosts=self._service_dns('kubernetes', 'default') + [
                'localhost', '127.0.0.1', 'apiserver.kubernetes.promenade'
            ] + [self.config['KubernetesNetwork:kubernetes.service_ip']])
        self.gen(
            'certificate',
            'apiserver-etcd',
            ca='kubernetes-etcd',
            cn='apiserver')

        # Certificates for other Kubernetes components
        self.gen(
            'certificate',
            'scheduler',
            ca='kubernetes',
            cn='system:kube-scheduler')
        self.gen(
            'certificate',
            'controller-manager',
            ca='kubernetes',
            cn='system:kube-controller-manager')
        self.gen('keypair', 'service-account')

        self.gen_kubelet_certificates()

        self.gen(
            'certificate', 'proxy', ca='kubernetes', cn='system:kube-proxy')

        # Certificates for kubectl admin
        self.gen(
            'certificate',
            'admin',
            ca='kubernetes',
            cn='admin',
            groups=['system:masters'])

        # Certificates for armada
        self.gen(
            'certificate',
            'armada',
            ca='kubernetes',
            cn='armada',
            groups=['system:masters'])

        # Certificates for coredns
        self.gen('certificate', 'coredns', ca='kubernetes', cn='coredns')

        # Certificates for Kubernetes's etcd servers
        self.gen_etcd_certificates(
            ca='kubernetes-etcd',
            genesis=True,
            service_name='kubernetes-etcd',
            service_namespace='kube-system',
            service_ip=self.config['KubernetesNetwork:etcd.service_ip'],
            additional_hosts=['etcd.kubernetes.promenade'])

        # Certificates for Calico's etcd servers
        self.gen_etcd_certificates(
            ca='calico-etcd',
            service_name='calico-etcd',
            service_namespace='kube-system',
            service_ip=self.calico_etcd_service_ip,
            additional_hosts=['etcd.calico.promenade'])

        # Certificates for Calico node
        self.gen(
            'certificate', 'calico-node', ca='calico-etcd', cn='calico-node')

        _write(output_dir, self.documents)

    def gen(self, kind, *args, **kwargs):
        method = getattr(self.keys, 'generate_' + kind)

        self.documents.extend(method(*args, **kwargs))

    def gen_kubelet_certificates(self):
        self._gen_single_kubelet(
            'genesis', node_data=self.config.get(kind='Genesis'))
        for node_config in self.config.iterate(kind='KubernetesNode'):
            self._gen_single_kubelet(
                node_config['data']['hostname'], node_data=node_config['data'])

    def _gen_single_kubelet(self, name, node_data):
        self.gen(
            'certificate',
            'kubelet-%s' % name,
            ca='kubernetes',
            cn='system:node:%s' % node_data['hostname'],
            hosts=[node_data['hostname'], node_data['ip']],
            groups=['system:nodes'])

    def gen_etcd_certificates(self, *, ca, genesis=False, **service_args):
        if genesis:
            self._gen_single_etcd(
                name='genesis',
                ca=ca,
                node_data=self.config.get(kind='Genesis'),
                **service_args)

        for node_config in self.config.iterate(kind='KubernetesNode'):
            self._gen_single_etcd(
                name=node_config['data']['hostname'],
                ca=ca,
                node_data=node_config['data'],
                **service_args)

        self.gen(
            'certificate',
            service_args['service_name'] + '-anchor',
            ca=ca,
            cn='anchor')

    def _gen_single_etcd(self,
                         *,
                         name,
                         ca,
                         node_data,
                         service_name,
                         service_namespace,
                         service_ip=None,
                         additional_hosts=None):
        member_name = ca + '-' + name

        hosts = [
            node_data['hostname'],
            node_data['ip'],
            'localhost',
            '127.0.0.1',
        ] + (additional_hosts or [])

        hosts.extend(self._service_dns(service_name, service_namespace))
        if service_ip is not None:
            hosts.append(service_ip)

        self.gen(
            'certificate', member_name, ca=ca, cn=member_name, hosts=hosts)

        self.gen(
            'certificate',
            member_name + '-peer',
            ca=ca + '-peer',
            cn=member_name,
            hosts=hosts)

    def _service_dns(self, name, namespace):
        return [
            name,
            '.'.join([name, namespace]),
            '.'.join([name, namespace, 'svc']),
            '.'.join([name, namespace, 'svc', self.cluster_domain]),
        ]


def _write(output_dir, docs):
    with open(os.path.join(output_dir, 'certificates.yaml'), 'w') as f:
        # Don't use safe_dump_all so we can block format certificate data.
        yaml.dump_all(
            docs,
            stream=f,
            default_flow_style=False,
            explicit_start=True,
            indent=2)
