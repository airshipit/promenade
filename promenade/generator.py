from . import logging, pki
import os
import yaml

__all__ = ['Generator']

LOG = logging.getLogger(__name__)


class Generator:
    def __init__(self, config):
        self.config = config
        self.keys = pki.PKI()
        self.documents = []

    @property
    def cluster_domain(self):
        return self.config['KubernetesNetwork:dns.cluster_domain']

    def generate(self, output_dir):
        for ca_name, ca_def in self.config[
                'PKICatalog:certificate_authorities'].items():
            self.gen('ca', ca_name)
            for cert_def in ca_def.get('certificates', []):
                hosts = cert_def.get('hosts', [])
                hosts.extend(
                    get_host_list(
                        cert_def.get('kubernetes_service_names', [])))
                self.gen(
                    'certificate',
                    cert_def['document_name'],
                    ca=ca_name,
                    cn=cert_def['common_name'],
                    hosts=hosts,
                    groups=cert_def.get('groups', []))
        for keypair_def in self.config['PKICatalog:keypairs']:
            self.gen('keypair', keypair_def['name'])
        _write(output_dir, self.documents)

    def gen(self, kind, *args, **kwargs):
        method = getattr(self.keys, 'generate_' + kind)

        self.documents.extend(method(*args, **kwargs))


def get_host_list(service_names):
    service_list = []
    for service in service_names:
        parts = service.split('.')
        for i in range(len(parts)):
            service_list.append('.'.join(parts[:i + 1]))
    return service_list


def _write(output_dir, docs):
    with open(os.path.join(output_dir, 'certificates.yaml'), 'w') as f:
        # Don't use safe_dump_all so we can block format certificate data.
        yaml.dump_all(
            docs,
            stream=f,
            default_flow_style=False,
            explicit_start=True,
            indent=2)
