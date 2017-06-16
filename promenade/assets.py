from promenade import logging
import os
import subprocess

__all__ = ['rsync']


LOG = logging.getLogger(__name__)


def rsync(*, src, dest):
    LOG.info('Syncing assets from "%s" to "%s".', src, dest)
    subprocess.run(['/usr/bin/rsync', '-r', os.path.join(src, ''), dest], check=True)
