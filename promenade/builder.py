from . import logging, renderer
import io
import itertools
import os
import requests
import tarfile

__all__ = ['Builder']

LOG = logging.getLogger(__name__)


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
            if 'content' in file_spec:
                data = file_spec['content']
            elif 'tar_url' in file_spec:
                data = _fetch_tar_content(
                    url=file_spec['tar_url'], path=file_spec['tar_path'])
            self._file_cache[path] = {
                'path': path,
                'data': data,
                'mode': file_spec['mode'],
            }

    @property
    def _file_specs(self):
        return itertools.chain(
            self.config.get_path('HostSystem:files', []),
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
        LOG.info('Building genesis script')
        sub_config = self.config.extract_genesis_config()
        tarball = renderer.build_tarball_from_roles(
            config=sub_config,
            roles=['common', 'genesis'],
            file_specs=self.file_cache.values())

        script = renderer.render_template(
            sub_config,
            template='scripts/genesis.sh',
            context={'tarball': tarball})

        _write_script(output_dir, 'genesis.sh', script)

        if self.validators:
            validate_script = renderer.render_template(
                sub_config, template='scripts/validate-genesis.sh')
            _write_script(output_dir, 'validate-genesis.sh', validate_script)

    def build_node(self, node_document, *, output_dir):
        node_name = node_document['metadata']['name']
        LOG.info('Building script for node %s', node_name)
        sub_config = self.config.extract_node_config(node_name)
        file_spec_paths = [
            f['path'] for f in self.config.get_path('HostSystem:files', [])
        ]
        file_specs = [self.file_cache[p] for p in file_spec_paths]
        tarball = renderer.build_tarball_from_roles(
            config=sub_config, roles=['common', 'join'], file_specs=file_specs)

        script = renderer.render_template(
            sub_config,
            template='scripts/join.sh',
            context={'tarball': tarball})

        _write_script(output_dir, _join_name(node_name), script)

        if self.validators:
            validate_script = renderer.render_template(
                sub_config, template='scripts/validate-join.sh')
            _write_script(output_dir, 'validate-%s.sh' % node_name,
                          validate_script)


def _fetch_tar_content(*, url, path):
    response = requests.get(url)
    response.raise_for_status()
    f = io.BytesIO(response.content)
    tf = tarfile.open(fileobj=f, mode='r')
    buf_reader = tf.extractfile(path)
    return buf_reader.read()


def _join_name(node_name):
    return 'join-%s.sh' % node_name


def _write_script(output_dir, name, script):
    path = os.path.join(output_dir, name)
    with open(path, 'w') as f:
        os.fchmod(f.fileno(), 0o555)
        f.write(script)
