from . import exceptions, logging, validation
from . import design_ref as dr
import docker
import jinja2
import jsonpath_ng
import os
import yaml

from deckhand.engine import layering
from deckhand import errors as dh_errors

__all__ = ['Configuration']

LOG = logging.getLogger(__name__)


class Configuration:
    def __init__(self,
                 *,
                 documents,
                 debug=False,
                 substitute=True,
                 allow_missing_substitutions=True,
                 extract_hyperkube=True,
                 leave_kubectl=False,
                 validate=True):
        LOG.info("Parsing document schemas.")
        LOG.info("Building config from %d documents." % len(documents))
        if substitute:
            LOG.info("Rendering documents via Deckhand engine.")
            try:
                deckhand_eng = layering.DocumentLayering(
                    documents,
                    fail_on_missing_sub_src=not allow_missing_substitutions)
                documents = [dict(d) for d in deckhand_eng.render()]
            except dh_errors.DeckhandException as e:
                LOG.exception(
                    'An unknown Deckhand exception occurred while trying'
                    ' to render documents.')
                raise exceptions.DeckhandException(str(e))

            LOG.info("Deckhand engine returned %d documents." % len(documents))
        self.debug = debug
        self.documents = documents
        self.extract_hyperkube = extract_hyperkube
        self.leave_kubectl = leave_kubectl

        if validate:
            validation.validate_all(self)

    @classmethod
    def from_streams(cls, *, streams, **kwargs):
        documents = []
        for stream in streams:
            stream_name = getattr(stream, 'name')
            if stream_name is not None:
                LOG.info('Loading documents from %s', stream_name)
            stream_documents = list(yaml.safe_load_all(stream))
            if stream_name is not None:
                LOG.info('Successfully loaded %d documents from %s',
                         len(stream_documents), stream_name)
            documents.extend(stream_documents)

        return cls(documents=documents, **kwargs)

    @classmethod
    def from_design_ref(cls, design_ref, ctx=None, **kwargs):
        documents, use_dh_engine = dr.get_documents(design_ref, ctx)

        return cls(
            documents=documents,
            substitute=use_dh_engine,
            validate=use_dh_engine,
            **kwargs)

    def __getitem__(self, path):
        return self.get_path(
            path, jinja2.StrictUndefined('No match found for path %s' % path))

    def get_first(self, *paths, default=None):
        result = self._get_first(*paths)
        if result:
            return result
        else:
            if default is not None:
                return default
            else:
                return jinja2.StrictUndefined(
                    'Nothing found matching paths: %s' % ','.join(paths))

    def get(self, *, kind=None, name=None, schema=None, default=None):
        result = _get(self.documents, kind=kind, schema=schema, name=name)

        if result:
            return result['data']
        else:
            if default is not None:
                return default
            else:
                return jinja2.StrictUndefined(
                    'No document found matching kind=%s schema=%s name=%s' %
                    (kind, schema, name))

    def iterate(self, *, kind=None, schema=None, labels=None, name=None):
        if kind is not None:
            if schema is not None:
                raise AssertionError(
                    'Logic error: specified both kind and schema')
            schema = 'promenade/%s/v1' % kind

        for document in self.documents:
            if _matches_filter(
                    document, schema=schema, labels=labels, name=name):
                yield document

    def find(self, *args, **kwargs):
        for doc in self.iterate(*args, **kwargs):
            return doc

    # try to use docker socket from ENV
    # supported the same way like for docker client
    def get_container_info(self):
        LOG.debug(
            'Getting access to Docker via socket and getting mount points')
        client = docker.from_env()
        try:
            client.ping()
        except Exception:
            raise Exception('Docker is not responding, check ENV vars')
        tmp_dir = os.getenv('PROMENADE_TMP')
        if tmp_dir is None:
            raise Exception('ERROR: undefined PROMENADE_TMP')
        tmp_dir_local = os.getenv('PROMENADE_TMP_LOCAL')
        if tmp_dir_local is None:
            raise Exception('ERROR: undefined PROMENADE_TMP_LOCAL')
        if not os.path.exists(tmp_dir_local):
            raise Exception('ERROR: {} not found'.format(tmp_dir_local))
        return {
            'client': client,
            'dir': tmp_dir,
            'dir_local': tmp_dir_local,
        }

    def extract_genesis_config(self):
        LOG.debug('Extracting genesis config.')
        documents = []
        for document in self.documents:
            if document['schema'] != 'promenade/KubernetesNode/v1':
                documents.append(document)
            else:
                LOG.debug('Excluding schema=%s metadata.name=%s',
                          document['schema'], _mg(document, 'name'))
        return Configuration(
            debug=self.debug,
            documents=documents,
            extract_hyperkube=self.extract_hyperkube,
            leave_kubectl=self.leave_kubectl,
            substitute=False,
            validate=False)

    def extract_node_config(self, name):
        LOG.debug('Extracting node config for %s.', name)
        documents = []
        for document in self.documents:
            schema = document['schema']
            if schema == 'promenade/Genesis/v1':
                LOG.debug('Excluding schema=%s metadata.name=%s', schema,
                          _mg(document, 'name'))
                continue
            elif schema == 'promenade/KubernetesNode/v1' and _mg(
                    document, 'name') != name:
                LOG.debug('Excluding schema=%s metadata.name=%s', schema,
                          _mg(document, 'name'))
                continue
            else:
                documents.append(document)
        return Configuration(
            debug=self.debug,
            documents=documents,
            extract_hyperkube=self.extract_hyperkube,
            leave_kubectl=self.leave_kubectl,
            substitute=False,
            validate=False)

    @property
    def kubelet_name(self):
        for document in self.iterate(kind='Genesis'):
            return 'genesis'

        for document in self.iterate(kind='KubernetesNode'):
            return document['data']['hostname']

        return jinja2.StrictUndefined(
            'No Genesis or KubernetesNode found while getting kubelet name')

    def _get_first(self, *paths):
        for path in paths:
            value = self.get_path(path)
            if value:
                return value

    @property
    def enable_units(self):
        """ Get systemd unit names where enable is ``true``."""
        return self.get_units_by_action('enable')

    @property
    def start_units(self):
        """ Get systemd unit names where start is ``true``."""
        return self.get_units_by_action('start')

    @property
    def stop_units(self):
        """ Get systemd unit names where stop is ``true``."""
        return self.get_units_by_action('stop')

    @property
    def disable_units(self):
        """ Get systemd unit names where disable is ``true``."""
        return self.get_units_by_action('disable')

    def get_units_by_action(self, action):
        """ Select systemd unit names by ``action``

        Get all units that are ``true`` for ``action``.
        """
        return [
            k for k, v in self.systemd_units.items() if v.get(action, False)
        ]

    @property
    def systemd_units(self):
        """ Return a dictionary of systemd units to be managed during join.

        The dictionary key is the systemd unit name, each will have a four
        boolean keys: ``enable``, ``disable``, ``start``, ``stop`` on the
        actions to be taken at the end of genesis/node join. The steps
        are ordered: enable, start, stop, disable.
        """
        all_units = {}

        for document in self.iterate(kind='HostSystem'):
            all_units.update(document['data'].get('systemd_units', {}))

        return all_units

    @property
    def join_ips(self):
        maybe_ips = self.get_path('KubernetesNode:join_ips')
        if maybe_ips is not None:
            return maybe_ips
        else:
            maybe_ip = self._get_first('KubernetesNode:join_ip', 'Genesis:ip')
            if maybe_ip:
                return [maybe_ip]
            else:
                return jinja2.StrictUndefined('Could not find join IPs')

    def get_path(self, path, default=None):
        kind, jsonpath = path.split(':')
        document = _get(self.documents, kind=kind)
        if document:
            data = _extract(document['data'], jsonpath)
            if data:
                return data
        return default

    def append(self, item):
        validation.check_schema(item)
        self.documents.append(item)

    def bootstrap_apiserver_prefix(self):
        return self.get_path('Genesis:apiserver.command_prefix',
                             ['kube-apiserver'])


def _matches_filter(document, *, schema, labels, name):
    matches = True
    if schema is not None and not document.get('schema',
                                               '').startswith(schema):
        matches = False

    if labels is not None:
        document_labels = _mg(document, 'labels', [])
        for key, value in labels.items():
            if key not in document_labels:
                matches = False
            else:
                if document_labels[key] != value:
                    matches = False

    if name is not None:
        if _mg(document, 'name') != name:
            matches = False

    return matches


def _get(documents, kind=None, schema=None, name=None):
    if kind is not None:
        if schema is not None:
            msg = "Only kind or schema may be specified, not both"
            raise exceptions.ValidationException(msg)
        schema = 'promenade/%s/v1' % kind

    for document in documents:
        if (schema == document.get('schema')
                and (name is None or name == _mg(document, 'name'))):
            return document


def _extract(document, jsonpath):
    p = jsonpath_ng.parse(jsonpath)
    matches = p.find(document)
    if matches:
        return matches[0].value


def _mg(document, field, default=None):
    return document.get('metadata', {}).get(field, default)
