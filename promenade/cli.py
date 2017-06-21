from . import generator, logging, operator
import click

__all__ = []


LOG = logging.getLogger(__name__)


@click.group()
@click.option('-v', '--verbose', is_flag=True)
def promenade(*, verbose):
    logging.setup(verbose=verbose)


@promenade.command(help='Initialize a new cluster on one node')
@click.option('-a', '--asset-dir', default='/assets',
              type=click.Path(exists=True, file_okay=False,
                              dir_okay=True, resolve_path=True),
              help='Source path for binaries to deploy.')
@click.option('-c', '--config-path', type=click.File(),
              help='Location of cluster configuration data.')
@click.option('--hostname', help='Current hostname.')
@click.option('-t', '--target-dir', default='/target',
              type=click.Path(exists=True, file_okay=False,
                              dir_okay=True, resolve_path=True),
              help='Location where templated files will be placed.')
def genesis(*, asset_dir, config_path, hostname, target_dir):

    op = operator.Operator.from_config(config_path=config_path,
                                       hostname=hostname,
                                       target_dir=target_dir)

    op.genesis(asset_dir=asset_dir)


@promenade.command(help='Join an existing cluster')
@click.option('-a', '--asset-dir', default='/assets',
              type=click.Path(exists=True, file_okay=False,
                              dir_okay=True, resolve_path=True),
              help='Source path for binaries to deploy.')
@click.option('-c', '--config-path', type=click.File(),
              help='Location of cluster configuration data.')
@click.option('--hostname', help='Current hostname.')
@click.option('-t', '--target-dir', default='/target',
              type=click.Path(exists=True, file_okay=False,
                              dir_okay=True, resolve_path=True),
              help='Location where templated files will be placed.')
def join(*, asset_dir, config_path, hostname, target_dir):

    op = operator.Operator.from_config(config_path=config_path,
                                       hostname=hostname,
                                       target_dir=target_dir)

    op.join(asset_dir=asset_dir)


@promenade.command(help='Generate certs and keys')
@click.option('-c', '--config-path', type=click.File(),
              required=True,
              help='Location of cluster configuration data.')
@click.option('-o', '--output-dir', default='.',
              type=click.Path(exists=True, file_okay=False, dir_okay=True,
                              resolve_path=True),
              required=True,
              help='Location to write complete cluster configuration.')
def generate(*, config_path, output_dir):
    g = generator.Generator.from_config(config_path=config_path)
    g.generate_all(output_dir)
