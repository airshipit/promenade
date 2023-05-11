from . import encryption_method, logging, renderer
from beaker.cache import CacheManager
from beaker.util import parse_cache_config_options

import io
import itertools
import os
import requests
import stat
import tarfile
import time

__all__ = ['Builder']

LOG = logging.getLogger(__name__)

# Ignore bandit false positive:
#   B108:hardcoded_tmp_directory
# This cache needs to be shared by all forks within the same container, and so
# must be at a well-known location.
TMP_CACHE = '/tmp/cache'  # nosec
CACHE_OPTS = {
    'cache.type': 'file',
    'cache.data_dir': TMP_CACHE + '/data',  # nosec
    'cache.lock_dir': TMP_CACHE + '/lock',  # nosec
}

CACHE = CacheManager(**parse_cache_config_options(CACHE_OPTS))


class Builder:

    def __init__(self, config, *, validators=False):
        self.config = config
        self.validators = validators
        self._file_cache = None

    @property
    def file_cache(self):
        if not self._file_cache:
            self._build_file_cache()
        return self._file_cache

    def _build_file_cache(self):
        self._file_cache = {}
        for file_spec in self._file_specs:
            path = file_spec['path']
            islink = False
            if 'content' in file_spec:
                data = file_spec['content']
            elif 'symlink' in file_spec:
                data = file_spec['symlink']
                islink = True
            elif 'url' in file_spec:
                data = _fetch_tar_url(file_spec['url'])
            elif 'tar_url' in file_spec:
                data = _fetch_tar_content(file_spec['tar_url'],
                                          file_spec['tar_path'])
            self._file_cache[path] = {
                'path': path,
                'data': data,
                'mode': file_spec['mode'],
                'islink': islink,
            }

    @property
    def _file_specs(self):
        return itertools.chain(self.config.get_path('HostSystem:files', []),
                               self.config.get_path('Genesis:files', []))

    def build_all(self, *, output_dir):
        self.build_genesis(output_dir=output_dir)
        for node_document in self.config.iterate(
                schema='promenade/KubernetesNode/v1'):
            self.build_node(node_document, output_dir=output_dir)

        if self.validators:
            validate_script = renderer.render_template(
                self.config, template='scripts/validate-cluster.sh')
            _write_script(output_dir, 'validate-cluster.sh', validate_script)

    def build_genesis(self, *, output_dir):
        script = self.build_genesis_script()
        _write_script(output_dir, 'genesis.sh', script)

        if self.validators:
            validate_script = self._build_genesis_validate_script()
            _write_script(output_dir, 'validate-genesis.sh', validate_script)

    def build_genesis_script(self):
        LOG.info('Building genesis script')
        genesis_roles = ['common', 'genesis']
        sub_config = self.config.extract_genesis_config()
        tarball = renderer.build_tarball_from_roles(
            config=sub_config,
            roles=genesis_roles,
            file_specs=self.file_cache.values())

        (encrypted_tarball, decrypt_setup_command, decrypt_command,
         decrypt_teardown_command) = _encrypt_genesis(sub_config, tarball)

        return renderer.render_template(sub_config,
                                        template='scripts/genesis.sh',
                                        context={
                                            'decrypt_command': decrypt_command,
                                            'decrypt_setup_command':
                                            decrypt_setup_command,
                                            'decrypt_teardown_command':
                                            decrypt_teardown_command,
                                            'encrypted_tarball':
                                            encrypted_tarball,
                                        },
                                        roles=genesis_roles)

    def _build_genesis_validate_script(self):
        sub_config = self.config.extract_genesis_config()
        return renderer.render_template(sub_config,
                                        template='scripts/validate-genesis.sh')

    def build_node(self, node_document, *, output_dir):
        node_name = node_document['metadata']['name']
        LOG.info('Building script for node %s', node_name)
        script = self.build_node_script(node_name)

        _write_script(output_dir, _join_name(node_name), script)

        if self.validators:
            validate_script = self._build_node_validate_script(node_name)
            _write_script(output_dir, 'validate-%s.sh' % node_name,
                          validate_script)

    def build_node_script(self, node_name):
        build_roles = ['common', 'join']
        sub_config = self.config.extract_node_config(node_name)
        file_spec_paths = [
            f['path'] for f in self.config.get_path('HostSystem:files', [])
        ]
        file_specs = [self.file_cache[p] for p in file_spec_paths]
        tarball = renderer.build_tarball_from_roles(config=sub_config,
                                                    roles=build_roles,
                                                    file_specs=file_specs)

        (encrypted_tarball, decrypt_setup_command, decrypt_command,
         decrypt_teardown_command) = _encrypt_node(sub_config, tarball)

        return renderer.render_template(sub_config,
                                        template='scripts/join.sh',
                                        context={
                                            'decrypt_command': decrypt_command,
                                            'decrypt_setup_command':
                                            decrypt_setup_command,
                                            'decrypt_teardown_command':
                                            decrypt_teardown_command,
                                            'encrypted_tarball':
                                            encrypted_tarball,
                                        },
                                        roles=build_roles)

    def _build_node_validate_script(self, node_name):
        sub_config = self.config.extract_node_config(node_name)
        return renderer.render_template(sub_config,
                                        template='scripts/validate-join.sh')


def _encrypt_genesis(config, data):
    return _encrypt(config.get_path('EncryptionPolicy:scripts.genesis'), data)


def _encrypt_node(config, data):
    return _encrypt(config.get_path('EncryptionPolicy:scripts.join'), data)


def _encrypt(cfg_dict, data):
    method = encryption_method.EncryptionMethod.from_config(cfg_dict)
    encrypted_data = method.encrypt(data)
    decrypt_setup_command = method.get_decrypt_setup_command()
    decrypt_command = method.get_decrypt_command()
    decrypt_teardown_command = method.get_decrypt_teardown_command()
    return (encrypted_data, decrypt_setup_command, decrypt_command,
            decrypt_teardown_command)


@CACHE.cache('fetch_tarball_content', expire=72 * 3600)
def _fetch_tar_content(url, path):
    content = _fetch_tar_url(url)
    f = io.BytesIO(content)
    tf = tarfile.open(fileobj=f, mode='r')
    buf_reader = tf.extractfile(path)
    return buf_reader.read()


@CACHE.cache('fetch_tarball_url', expire=72 * 3600)
def _fetch_tar_url(url):
    LOG.debug('Fetching url=%s', url)
    # NOTE(mark-burnett): Retry with linear backoff until we are killed, e.g.
    # by a timeout.
    for attempt in itertools.count():
        try:
            response = requests.get(url, timeout=None)
            response.raise_for_status()
            break
        except requests.exceptions.RequestException:
            backoff = 5 * attempt
            LOG.exception('Failed to fetch %s, retrying in %d seconds', url,
                          backoff)
            time.sleep(backoff)

    LOG.debug('Finished downloading url=%s', url)
    return response.content


def _join_name(node_name):
    return 'join-%s.sh' % node_name


def _write_script(output_dir, name, script):
    path = os.path.join(output_dir, name)
    with open(path, 'w') as f:
        f.write(script)

    os.chmod(
        path,
        os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
