from . import logging
import json
import os
# Ignore bandit false positive: B404:blacklist
# The purpose of this module is to safely encapsulate calls via fork.
import subprocess  # nosec
import tempfile
import yaml

__all__ = ['PKI']

LOG = logging.getLogger(__name__)


class PKI:
    def __init__(self, *, block_strings=True):
        self.block_strings = block_strings
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
        result = self._cfssl(['gencert', '-initca', 'csr.json'],
                             files={
                                 'csr.json':
                                 self.csr(name=ca_name, groups=['Kubernetes']),
                             })

        return (self._wrap_ca(ca_name, result['cert']),
                self._wrap_ca_key(ca_name, result['key']))

    def generate_keypair(self, name):
        priv_result = self._openssl(['genrsa', '-out', 'priv.pem'])
        pub_result = self._openssl(
            ['rsa', '-in', 'priv.pem', '-pubout', '-out', 'pub.pem'],
            files={
                'priv.pem': priv_result['priv.pem'],
            })

        return (self._wrap_pub_key(name, pub_result['pub.pem']),
                self._wrap_priv_key(name, priv_result['priv.pem']))

    def generate_certificate(self,
                             name,
                             *,
                             ca_cert,
                             ca_key,
                             cn,
                             groups=None,
                             hosts=None):
        if groups is None:
            groups = []
        if hosts is None:
            hosts = []

        result = self._cfssl(
            [
                'gencert', '-ca', 'ca.pem', '-ca-key', 'ca-key.pem', '-config',
                'ca-config.json', 'csr.json'
            ],
            files={
                'ca-config.json': self.ca_config,
                'ca.pem': ca_cert,
                'ca-key.pem': ca_key,
                'csr.json': self.csr(name=cn, groups=groups, hosts=hosts),
            })

        return (self._wrap_cert(name, result['cert']),
                self._wrap_cert_key(name, result['key']))

    def csr(self,
            *,
            name,
            groups=None,
            hosts=None,
            key={
                'algo': 'rsa',
                'size': 2048
            }):
        if groups is None:
            groups = []
        if hosts is None:
            hosts = []

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

            # Ignore bandit false positive:
            #   B603:subprocess_without_shell_equals_true
            # This method wraps cfssl calls originating from this module.
            result = subprocess.check_output(  # nosec
                ['cfssl'] + command, cwd=tmp, stderr=subprocess.PIPE)
            if not isinstance(result, str):
                result = result.decode('utf-8')
            return json.loads(result)

    def _openssl(self, command, *, files=None):
        if not files:
            files = {}

        with tempfile.TemporaryDirectory() as tmp:
            for filename, data in files.items():
                with open(os.path.join(tmp, filename), 'w') as f:
                    f.write(data)

            # Ignore bandit false positive:
            #   B603:subprocess_without_shell_equals_true
            # This method wraps openssl calls originating from this module.
            subprocess.check_call(  # nosec
                ['openssl'] + command,
                cwd=tmp,
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
                'layeringDefinition': {
                    'abstract': False,
                    'layer': 'site',
                },
                'storagePolicy': 'cleartext',
            },
            'data': self._block_literal(data),
        }

    def _block_literal(self, data):
        if self.block_strings:
            return block_literal(data)
        else:
            return data


class block_literal(str):
    pass


def block_literal_representer(dumper, data):
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')


yaml.add_representer(block_literal, block_literal_representer)
