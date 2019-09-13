from . import builder, config, exceptions, generator, logging, options
import click
import os
import sys

__all__ = []

options.setup()
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
@click.option(
    '--extract-hyperkube',
    is_flag=True,
    default=False,
    help='Extract hyperkube binary from image')
@click.option(
    '--leave-kubectl',
    is_flag=True,
    help='Leave behind kubectl on joined nodes')
@click.argument('config_files', nargs=-1, type=click.File('rb'))
def build_all(*, config_files, extract_hyperkube, leave_kubectl, output_dir,
              validators):
    debug = _debug()
    try:
        c = config.Configuration.from_streams(
            debug=debug,
            substitute=True,
            allow_missing_substitutions=False,
            extract_hyperkube=extract_hyperkube,
            leave_kubectl=leave_kubectl,
            streams=config_files)
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
def generate_certs(*, config_files, output_dir):
    debug = _debug()
    try:
        c = config.Configuration.from_streams(
            debug=debug,
            streams=config_files,
            substitute=True,
            allow_missing_substitutions=True,
            validate=False)
        g = generator.Generator(c)
        g.generate(output_dir)
    except exceptions.PromenadeException as e:
        e.display(debug=debug)
        sys.exit(e.EXIT_CODE)


def _debug():
    return os.environ.get('PROMENADE_DEBUG', '').lower() in {'1', 'true'}
