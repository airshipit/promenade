from . import config, logging
import json
import os
import subprocess
import tempfile
import yaml

__all__ = ['PKI']


LOG = logging.getLogger(__name__)


class PKI:
    def __init__(self, cluster_name, *, ca_config=None):
        self.certificate_authorities = {}
        self.cluster_name = cluster_name

        self._ca_config_string = None
        if ca_config:
            self._ca_config_string = json.dumps(ca_config)

    @property
    def ca_config(self):
        if not self._ca_config_string:
            self._ca_config_string = json.dumps({
                'signing': {
                    'default': {
                        'expiry': '8760h',
                        'usages': ['signing', 'key encipherment', 'server auth', 'client auth'],
                    },
                },
            })
        return self._ca_config_string

    def generate_ca(self, *, ca_name, cert_target, key_target):
        result = self._cfssl(['gencert', '-initca', 'csr.json'],
                             files={
                                 'csr.json': self.csr(
                                     name='Kubernetes',
                                     groups=['Kubernetes']),
                             })
        LOG.debug('ca_cert=%r', result['cert'])
        self.certificate_authorities[ca_name] = result

        return (self._wrap('CertificateAuthority', result['cert'],
                           name=ca_name,
                           target=cert_target),
                self._wrap('CertificateAuthorityKey', result['key'],
                           name=ca_name,
                           target=key_target))

    def generate_keypair(self, *, alias=None, name, target):
        priv_result = self._openssl(['genrsa', '-out', 'priv.pem'])
        pub_result = self._openssl(['rsa', '-in', 'priv.pem', '-pubout', '-out', 'pub.pem'],
                                   files={
                                       'priv.pem': priv_result['priv.pem'],
                                   })

        if not alias:
            alias = name

        return (self._wrap('PublicKey', pub_result['pub.pem'],
                           alias=alias,
                           name=name,
                           target=target),
                self._wrap('PrivateKey', priv_result['priv.pem'],
                           alias=alias,
                           name=name,
                           target=target))


    def generate_certificate(self, *, alias=None, config_name=None,
                             ca_name, groups=[], hosts=[], name, target):
        result = self._cfssl(
                ['gencert',
                 '-ca', 'ca.pem',
                 '-ca-key', 'ca-key.pem',
                 '-config', 'ca-config.json',
                 'csr.json'],
                files={
                    'ca-config.json': self.ca_config,
                    'ca.pem': self.certificate_authorities[ca_name]['cert'],
                    'ca-key.pem': self.certificate_authorities[ca_name]['key'],
                    'csr.json': self.csr(name=name, groups=groups, hosts=hosts),
                })

        if not alias:
            alias = name

        if not config_name:
            config_name = name

        return (self._wrap('Certificate', result['cert'],
                           alias=alias,
                           name=config_name,
                           target=target),
                self._wrap('CertificateKey', result['key'],
                           alias=alias,
                           name=config_name,
                           target=target))

    def csr(self, *, name, groups=[], hosts=[], key={'algo': 'rsa', 'size': 2048}):
        return json.dumps({
            'CN': name,
            'key': key,
            'hosts': hosts,
            'names': [{'O': g} for g in groups],
        })

    def _cfssl(self, command, *, files=None):
        if not files:
            files = {}
        with tempfile.TemporaryDirectory() as tmp:
            for filename, data in files.items():
                with open(os.path.join(tmp, filename), 'w') as f:
                    f.write(data)

            return json.loads(subprocess.check_output(
                ['cfssl'] + command, cwd=tmp))

    def _openssl(self, command, *, files=None):
        if not files:
            files = {}

        with tempfile.TemporaryDirectory() as tmp:
            for filename, data in files.items():
                with open(os.path.join(tmp, filename), 'w') as f:
                    f.write(data)

            subprocess.check_call(['openssl'] + command, cwd=tmp)

            result = {}
            for filename in os.listdir(tmp):
                if filename not in files:
                    with open(os.path.join(tmp, filename)) as f:
                        result[filename] = f.read()

            return result

    def _wrap(self, kind, data, **metadata):
        return config.Document({
            'apiVersion': 'promenade/v1',
            'kind': kind,
            'metadata': {
                'cluster': self.cluster_name,
                **metadata,
            },
            'spec': {
                'data': block_literal(data),
            },
        })


class block_literal(str): pass


def block_literal_representer(dumper, data):
    return dumper.represent_scalar(u'tag:yaml.org,2002:str', data, style='|')


yaml.add_representer(block_literal, block_literal_representer)
