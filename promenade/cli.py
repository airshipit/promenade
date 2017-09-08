from . import builder, config, exceptions, generator, logging
import click
import os
import sys

__all__ = []

LOG = logging.getLogger(__name__)


@click.group()
@click.option('-v', '--verbose', is_flag=True)
def promenade(*, verbose):
    if _debug():
        verbose = True
    logging.setup(verbose=verbose)


@promenade.command('build-all', help='Construct all scripts')
@click.option(
    '-o',
    '--output-dir',
    default='.',
    type=click.Path(
        exists=True, file_okay=False, dir_okay=True, resolve_path=True),
    required=True,
    help='Location to write complete cluster configuration.')
@click.option('--validators', is_flag=True, help='Generate validation scripts')
@click.argument('config_files', nargs=-1, type=click.File('rb'))
def build_all(*, config_files, output_dir, validators):
    debug = _debug()
    try:
        c = config.Configuration.from_streams(
            debug=debug, streams=config_files)
        b = builder.Builder(c, validators=validators)
        b.build_all(output_dir=output_dir)
    except exceptions.PromenadeException as e:
        e.display(debug=debug)
        sys.exit(e.EXIT_CODE)


@promenade.command('generate-certs', help='Generate a certs for a site')
@click.option(
    '-o',
    '--output-dir',
    type=click.Path(
        exists=True, file_okay=False, dir_okay=True, resolve_path=True),
    required=True,
    help='Location to write *-certificates.yaml')
@click.argument('config_files', nargs=-1, type=click.File('rb'))
@click.option(
    '--calico-etcd-service-ip',
    default='10.96.232.136',
    help='Service IP for calico etcd')
def genereate_certs(*, calico_etcd_service_ip, config_files, output_dir):
    debug = _debug()
    try:
        c = config.Configuration.from_streams(
            debug=debug, streams=config_files, substitute=False)
        g = generator.Generator(
            c, calico_etcd_service_ip=calico_etcd_service_ip)
        g.generate(output_dir)
    except exceptions.PromenadeException as e:
        e.display(debug=debug)
        sys.exit(e.EXIT_CODE)


def _debug():
    return os.environ.get('PROMENADE_DEBUG', '').lower() in {'1', 'True'}
