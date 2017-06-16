from . import kube, logging

__all__ = ['add_member']


LOG = logging.getLogger(__name__)


def add_member(exec_pod, hostname, port):
    opts = ' '.join([
        '--cacert',
        '/etc/etcd-pki/cluster-ca.pem',
        '--cert',
        '/etc/etcd-pki/etcd.pem',
        '--key',
        '/etc/etcd-pki/etcd-key.pem',
    ])
    result = kube.kc('exec', '-n', 'kube-system', '-t', exec_pod, '--', 'sh', '-c',
                     'ETCDCTL_API=3 etcdctl %s member add %s --peer-urls https://%s:%d'
                     % (opts, hostname, hostname, port))
    if result.returncode != 0:
        LOG.error('Failed to add etcd member. STDOUT: %r', result.stdout)
        LOG.error('Failed to add etcd member. STDERR: %r', result.stderr)
        result.check_returncode()
