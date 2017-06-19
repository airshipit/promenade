from . import config, logging, renderer
import os
import subprocess

__all__ = ['Operator']


LOG = logging.getLogger(__name__)


class Operator:
    @classmethod
    def from_config(cls, *, config_path, hostname, target_dir):
        return cls(hostname=hostname, target_dir=target_dir,
                   config_=config.load(config_path))

    def __init__(self, *, config_, hostname, target_dir):
        self.config = config_
        self.hostname = hostname
        self.target_dir = target_dir

    def genesis(self, *, asset_dir=None):
        self.setup(asset_dir=asset_dir)

    def join(self, *, asset_dir=None):
        self.setup(asset_dir=asset_dir)

    def setup(self, *, asset_dir):
        self.rsync_from(asset_dir)
        self.render()

        self.bootstrap()

    def rsync_from(self, src):
        if src:
            LOG.debug('Syncing assets from "%s" to "%s".', src, self.target_dir)
            subprocess.run(['/usr/bin/rsync', '-r',
                            os.path.join(src, ''), self.target_dir],
                           check=True)
        else:
            LOG.debug('No source directory given for rsync.')


    def render(self):
        r = renderer.Renderer(config=self.config,
                              target_dir=self.target_dir)
        r.render()

    def bootstrap(self):
        LOG.debug('Running genesis script with chroot "%s"', self.target_dir)
        subprocess.run([os.path.join(self.target_dir, 'usr/sbin/chroot'),
                        self.target_dir,
                        '/bin/bash', '/usr/local/bin/bootstrap'],
                       check=True)
