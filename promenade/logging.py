import logging
from logging import getLogger

__all__ = ['getLogger', 'setup']

LOG_FORMAT = '%(asctime)s %(levelname)-8s %(name)s:%(funcName)s [%(lineno)3d] %(message)s'  # noqa


def setup(*, verbose):
    if verbose:
        level = logging.DEBUG
    else:
        level = logging.INFO
    logging.basicConfig(format=LOG_FORMAT, level=level)
