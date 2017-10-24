from . import logging
import json
import os
import subprocess
import tempfile
import yaml

__all__ = ['PKI']

LOG = logging.getLogger(__name__)


class PKI:
    def __init__(self):
        self.certificate_authorities = {}
        self._ca_config_string = None

    @property
    def ca_config(self):
        if not self._ca_config_string:
            self._ca_config_string = json.dumps({
                'signing': {
                    'default': {
                        'expiry':
                        '8760h',
                        'usages': [
                            'signing', 'key encipherment', 'server auth',
                            'client auth'
                        ],
                    },
                },
            })
        return self._ca_config_string

    def generate_ca(self, ca_name):
        result = self._cfssl(
            ['gencert', '-initca', 'csr.json'],
            files={
                'csr.json': self.csr(name=ca_name, groups=['Kubernetes']),
            })
        self.certificate_authorities[ca_name] = result

        return (self._wrap_ca(ca_name, result['cert']), self._wrap_ca_key(
            ca_name, result['key']))

    def generate_keypair(self, name):
        priv_result = self._openssl(['genrsa', '-out', 'priv.pem'])
        pub_result = self._openssl(
            ['rsa', '-in', 'priv.pem', '-pubout', '-out', 'pub.pem'],
            files={
                'priv.pem': priv_result['priv.pem'],
            })

        return (self._wrap_pub_key(name, pub_result['pub.pem']),
                self._wrap_priv_key(name, priv_result['priv.pem']))

    def generate_certificate(self, name, *, ca, cn, groups=[], hosts=[]):
        result = self._cfssl(
            [
                'gencert', '-ca', 'ca.pem', '-ca-key', 'ca-key.pem', '-config',
                'ca-config.json', 'csr.json'
            ],
            files={
                'ca-config.json': self.ca_config,
                'ca.pem': self.certificate_authorities[ca]['cert'],
                'ca-key.pem': self.certificate_authorities[ca]['key'],
                'csr.json': self.csr(name=cn, groups=groups, hosts=hosts),
            })

        return (self._wrap_cert(name, result['cert']), self._wrap_cert_key(
            name, result['key']))

    def csr(self,
            *,
            name,
            groups=[],
            hosts=[],
            key={'algo': 'rsa',
                 'size': 2048}):
        return json.dumps({
            'CN': name,
            'key': key,
            'hosts': hosts,
            'names': [{
                'O': g
            } for g in groups],
        })

    def _cfssl(self, command, *, files=None):
        if not files:
            files = {}
        with tempfile.TemporaryDirectory() as tmp:
            for filename, data in files.items():
                with open(os.path.join(tmp, filename), 'w') as f:
                    f.write(data)

            return json.loads(
                subprocess.check_output(['cfssl'] + command, cwd=tmp,
                                        stderr=subprocess.PIPE))

    def _openssl(self, command, *, files=None):
        if not files:
            files = {}

        with tempfile.TemporaryDirectory() as tmp:
            for filename, data in files.items():
                with open(os.path.join(tmp, filename), 'w') as f:
                    f.write(data)

            subprocess.check_call(['openssl'] + command, cwd=tmp,
                                  stderr=subprocess.PIPE)

            result = {}
            for filename in os.listdir(tmp):
                if filename not in files:
                    with open(os.path.join(tmp, filename)) as f:
                        result[filename] = f.read()

            return result

    def _wrap_ca(self, name, data):
        return self._wrap(kind='CertificateAuthority', name=name, data=data)

    def _wrap_ca_key(self, name, data):
        return self._wrap(kind='CertificateAuthorityKey', name=name, data=data)

    def _wrap_cert(self, name, data):
        return self._wrap(kind='Certificate', name=name, data=data)

    def _wrap_cert_key(self, name, data):
        return self._wrap(kind='CertificateKey', name=name, data=data)

    def _wrap_priv_key(self, name, data):
        return self._wrap(kind='PrivateKey', name=name, data=data)

    def _wrap_pub_key(self, name, data):
        return self._wrap(kind='PublicKey', name=name, data=data)

    def _wrap(self, *, data, kind, name):
        return {
            'schema': 'deckhand/%s/v1' % kind,
            'metadata': {
                'schema': 'metadata/Document/v1',
                'name': name,
                'layerinDefinition': {
                    'abstract': False,
                    'layer': 'site',
                },
            },
            'data': block_literal(data),
        }


class block_literal(str):
    pass


def block_literal_representer(dumper, data):
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')


yaml.add_representer(block_literal, block_literal_representer)
