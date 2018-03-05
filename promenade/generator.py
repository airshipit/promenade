from . import exceptions, logging, pki
import collections
import itertools
import os
import yaml

__all__ = ['Generator']

LOG = logging.getLogger(__name__)


class Generator:
    def __init__(self, config):
        self.config = config
        self.keys = pki.PKI()
        self.documents = []
        self.outputs = collections.defaultdict(dict)

    @property
    def cluster_domain(self):
        return self.config['KubernetesNetwork:dns.cluster_domain']

    def generate(self, output_dir):
        for catalog in self.config.iterate(kind='PKICatalog'):
            for ca_name, ca_def in catalog['data'].get(
                    'certificate_authorities', {}).items():
                ca_cert, ca_key = self.get_or_gen_ca(ca_name)

                for cert_def in ca_def.get('certificates', []):
                    document_name = cert_def['document_name']
                    cert, key = self.get_or_gen_cert(
                        document_name,
                        ca_cert=ca_cert,
                        ca_key=ca_key,
                        cn=cert_def['common_name'],
                        hosts=_extract_hosts(cert_def),
                        groups=cert_def.get('groups', []))

            for keypair_def in catalog['data'].get('keypairs', []):
                document_name = keypair_def['name']
                self.get_or_gen_keypair(document_name)

        self._write(output_dir)

    def get_or_gen_ca(self, document_name):
        kinds = [
            'CertificateAuthority',
            'CertificateAuthorityKey',
        ]
        return self._get_or_gen(self.gen_ca, kinds, document_name)

    def get_or_gen_cert(self, document_name, **kwargs):
        kinds = [
            'Certificate',
            'CertificateKey',
        ]
        return self._get_or_gen(self.gen_cert, kinds, document_name, **kwargs)

    def get_or_gen_keypair(self, document_name):
        kinds = [
            'PublicKey',
            'PrivateKey',
        ]
        return self._get_or_gen(self.gen_keypair, kinds, document_name)

    def gen_ca(self, document_name, **kwargs):
        return self.keys.generate_ca(document_name, **kwargs)

    def gen_cert(self, document_name, *, ca_cert, ca_key, **kwargs):
        ca_cert_data = ca_cert['data']
        ca_key_data = ca_key['data']
        return self.keys.generate_certificate(
            document_name, ca_cert=ca_cert_data, ca_key=ca_key_data, **kwargs)

    def gen_keypair(self, document_name):
        return self.keys.generate_keypair(document_name)

    def _get_or_gen(self, generator, kinds, document_name, *args, **kwargs):
        docs = self._find_docs(kinds, document_name)
        if not docs:
            docs = generator(document_name, *args, **kwargs)

        # Adding these to output should be idempotent, so we use a dict.
        for doc in docs:
            self.outputs[doc['schema']][doc['metadata']['name']] = doc

        return docs

    def _find_docs(self, kinds, document_name):
        schemas = ['deckhand/%s/v1' % k for k in kinds]
        docs = self._find_in_config(schemas, document_name)
        if docs:
            if len(docs) == len(kinds):
                LOG.debug('Found docs in input config named %s, kinds: %s',
                          document_name, kinds)
                return docs
            else:
                raise exceptions.IncompletePKIPairError(
                    'Incomplete set %s '
                    'for name: %s' % (kinds, document_name))

        else:
            docs = self._find_in_outputs(schemas, document_name)
            if docs:
                LOG.debug('Found docs in current outputs named %s, kinds: %s',
                          document_name, kinds)
                return docs
            else:
                LOG.debug('No docs existing docs named %s, kinds: %s',
                          document_name, kinds)
                return []

    def _find_in_config(self, schemas, document_name):
        result = []
        for schema in schemas:
            doc = self.config.find(schema=schema, name=document_name)
            if doc:
                result.append(doc)
        return result

    def _find_in_outputs(self, schemas, document_name):
        result = []
        for schema in schemas:
            if document_name in self.outputs.get(schema, {}):
                result.append(self.outputs[schema][document_name])
        return result

    def _write(self, output_dir):
        docs = list(
            itertools.chain.from_iterable(
                v.values() for v in self.outputs.values()))
        with open(os.path.join(output_dir, 'certificates.yaml'), 'w') as f:
            # Don't use safe_dump_all so we can block format certificate data.
            yaml.dump_all(
                docs,
                stream=f,
                default_flow_style=False,
                explicit_start=True,
                indent=2)


def get_host_list(service_names):
    service_list = []
    for service in service_names:
        parts = service.split('.')
        for i in range(len(parts)):
            service_list.append('.'.join(parts[:i + 1]))
    return service_list


def _extract_hosts(cert_def):
    hosts = cert_def.get('hosts', [])
    hosts.extend(get_host_list(cert_def.get('kubernetes_service_names', [])))
    return hosts
