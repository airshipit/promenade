from . import logging
import subprocess
import time

__all__ = ['kc', 'wait_for_node']


LOG = logging.getLogger(__name__)


def wait_for_node(node):
    repeat = True
    while repeat:
        result = kc('get', 'nodes', node, '-o',
                    r'jsonpath={.status.conditions[?(@.type=="Ready")].status}')
        if result.stdout == b'True':
            repeat = False
        else:
            LOG.debug('Node "%s" not ready, waiting. stdout=%r stderr=%r',
                      node, result.stdout, result.stderr)
            time.sleep(5)


def kc(*args):
    return subprocess.run(['/target/usr/local/bin/kubectl',
        '--kubeconfig', '/target/etc/kubernetes/genesis/kubeconfig.yaml', *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
