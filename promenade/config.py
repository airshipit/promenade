from . import logging
from operator import attrgetter, itemgetter
import itertools
import yaml

__all__ = ['Configuration', 'Document', 'load']


LOG = logging.getLogger(__name__)


def load(f):
    return Configuration(list(map(Document, yaml.load_all(f))))


class Document:
    KEYS = {
        'apiVersion',
        'metadata',
        'kind',
        'spec',
    }

    SUPPORTED_KINDS = {
        'Certificate',
        'CertificateAuthority',
        'CertificateAuthorityKey',
        'CertificateKey',
        'Cluster',
        'Etcd',
        'Masters',
        'Network',
        'Node',
        'PrivateKey',
        'PublicKey',
    }

    def __init__(self, data):
        if set(data.keys()) != self.KEYS:
            LOG.error('data.keys()=%s expected %s', data.keys(), self.KEYS)
            raise AssertionError('Did not get expected keys')
        assert data['apiVersion'] == 'promenade/v1'
        assert data['kind'] in self.SUPPORTED_KINDS

        self.data = data

    @property
    def kind(self):
        return self.data['kind']

    @property
    def target(self):
        return self.metadata.get('target')

    @property
    def metadata(self):
        return self.data['metadata']

    def __getitem__(self, key):
        return self.data['spec'][key]


class Configuration:
    def __init__(self, documents):
        self.documents = sorted(documents, key=attrgetter('kind', 'target'))

    def __getitem__(self, key):
        results = [d for d in self.documents if d.kind == key]
        if len(results) < 1:
            raise KeyError
        elif len(results) > 1:
            raise KeyError('Too many results.')
        else:
            return results[0]

    def iterate(self, *, kind=None, target=None):
        if target:
            docs = self._iterate_with_target(target)
        else:
            docs = self.documents

        for document in docs:
            if not kind or document.kind == kind:
                yield document

    def _iterate_with_target(self, target):
        for document in self.documents:
            if document.target == target or document.target == 'all':
                yield document

    def write(self, path):
        with open(path, 'w') as f:
            yaml.dump_all(map(attrgetter('data'), self.documents),
                          default_flow_style=False,
                          explicit_start=True,
                          indent=2,
                          stream=f)
