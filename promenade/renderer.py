from . import exceptions, logging, tar_bundler
import base64
import datetime
import io
import jinja2
import os
import pkg_resources
import yaml

__all__ = [
    'build_tarball_from_roles', 'insert_charts_into_bundler',
    'render_role_into_bundler'
]

LOG = logging.getLogger(__name__)


def build_tarball_from_roles(config, *, roles, file_specs):
    bundler = tar_bundler.TarBundler()
    for role in roles:
        render_role_into_bundler(bundler=bundler, config=config, role=role)

    for file_spec in file_specs:
        bundler.add(**file_spec)

    if 'genesis' in roles:
        insert_charts_into_bundler(bundler)

    return bundler.as_blob()


def insert_charts_into_bundler(bundler):
    for root, _dirnames, filenames in os.walk(
            '/opt/promenade/charts', followlinks=True):
        for source_filename in filenames:
            if _source_file_is_excluded(source_filename):
                continue
            source_path = os.path.join(root, source_filename)
            destination_path = os.path.join(
                'etc/genesis/armada/assets/charts',
                os.path.relpath(source_path, '/opt/promenade/charts'))
            stat = os.stat(source_path)
            LOG.debug('Copying asset file %s (mode=%o)', source_path,
                      stat.st_mode)
            with open(source_path) as f:
                bundler.add(
                    path=destination_path, data=f.read(), mode=stat.st_mode)


def render_role_into_bundler(*, bundler, config, role):
    role_root = pkg_resources.resource_filename(
        'promenade', os.path.join('templates', 'roles', role))
    for root, _dirnames, filenames in os.walk(role_root, followlinks=True):
        destination_base = os.path.relpath(root, role_root)
        for source_filename in filenames:
            source_path = os.path.join(root, source_filename)
            stat = os.stat(source_path)
            LOG.debug('Rendering file %s (mode=%o)', source_path, stat.st_mode)
            destination_path = os.path.join(destination_base, source_filename)
            render_template_into_bundler(
                bundler=bundler,
                config=config,
                destination_path=destination_path,
                source_path=source_path,
                mode=stat.st_mode)


def render_template_into_bundler(*, bundler, config, destination_path,
                                 source_path, mode):
    env = _build_env()

    with open(source_path) as f:
        template = env.from_string(f.read())
    now = int(datetime.datetime.utcnow().timestamp())
    try:
        data = template.render(config=config, now=now)
    except jinja2.exceptions.TemplateRuntimeError as e:
        LOG.exception('Error rendering template (%s)' % source_path)
        raise exceptions.TemplateRenderException(
            'Error rendering template (%s): %s' % (source_path, e))

    bundler.add(path=destination_path, data=data, mode=mode)


def render_template(config, *, template, context=None):
    if context is None:
        context = {}

    template_contents = pkg_resources.resource_string(
        'promenade', os.path.join('templates', template))

    env = _build_env()

    template_obj = env.from_string(template_contents.decode('utf-8'))
    try:
        return template_obj.render(config=config, **context)
    except jinja2.exceptions.TemplateRuntimeError as e:
        LOG.exception('Error rendering template (%s)' % template)
        raise exceptions.TemplateRenderException(
            'Error rendering template (%s): %s' % (template, e))


def _build_env():
    # Ignore bandit false positive: B701:jinja2_autoescape_false
    # This env is not used to render content that is vulnerable to XSS.
    env = jinja2.Environment(  # nosec
        loader=jinja2.PackageLoader('promenade', 'templates/include'),
        undefined=jinja2.StrictUndefined)
    env.filters['b64enc'] = _base64_encode
    env.filters['fill_no_proxy'] = _fill_no_proxy
    env.filters['yaml_safe_dump_all'] = _yaml_safe_dump_all
    env.filters['toyaml'] = _yaml_safe_dump_arg
    return env


def _base64_encode(s):
    try:
        return base64.b64encode(s).decode()
    except TypeError:
        return base64.b64encode(s.encode()).decode()


def _fill_no_proxy(network_config):
    proxy = network_config.get('proxy', {}).get('url')
    if proxy:
        additional = network_config.get('proxy', {}).get(
            'additional_no_proxy', [])
        if additional:
            return ','.join(additional) + ',' + _default_no_proxy(
                network_config)
        else:
            return _default_no_proxy(network_config)
    else:
        return ''


def _default_no_proxy(network_config):
    # XXX We can add better default data.
    include = [
        '127.0.0.1',
        'localhost',
        'kubernetes',
        'kubernetes.default',
        'kubernetes.default.svc',
        'kubernetes.default.svc.%s' % network_config.get('dns', {}).get(
            'cluster_domain', 'cluster.local'),
    ]
    return ','.join(include)


def _source_file_is_excluded(source_filename):
    return source_filename.endswith('.tgz')


def _yaml_safe_dump_all(documents):
    f = io.StringIO()
    yaml.safe_dump_all(documents, f)
    return f.getvalue()


def _yaml_safe_dump_arg(data):
    f = io.StringIO()
    yaml.safe_dump(data, f, explicit_start=False, explicit_end=False)
    return f.getvalue()
