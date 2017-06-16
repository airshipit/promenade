from . import logging
from operator import itemgetter
import itertools
import yaml

__all__ = ['load_config_file']


LOG = logging.getLogger(__name__)


def load_config_file(*, config_path, hostname):
    LOG.debug('Loading genesis configuration from "%s"', config_path)
    cluster_data = yaml.load(open(config_path))
    LOG.debug('Loaded genesis configruation from "%s"', config_path)
    node_data = extract_node_data(hostname, cluster_data)

    return {
        'cluster_data': cluster_data,
        'node_data': node_data,
    }


def extract_node_data(hostname, cluster_data):
    genesis = _extract_genesis_data(cluster_data['nodes'])
    masters = _extract_master_data(cluster_data['nodes'])
    return {
        'cluster': cluster_data['nodes'],
        'current_node': _extract_current_node_data(cluster_data['nodes'],
                                                   hostname),
        'etcd': _extract_etcd_data(hostname, genesis, masters),
        'genesis': genesis,
        'masters': masters,
        'network': cluster_data['network'],
    }


def _extract_etcd_data(hostname, genesis, masters):
    LOG.info('hostname=%r genesis=%r masters=%r',
             hostname, genesis, masters)
    non_genesis_masters = [d for d in masters if d['hostname'] != genesis['hostname']]
    boot_order = [genesis] + sorted(non_genesis_masters, key=itemgetter('hostname'))

    result = {
        'boot_order': boot_order,
        'env': {},
    }

    peers = []
    for host in boot_order:
        peers.append(host)
        if host['hostname'] == hostname:
            break

    result['env']['ETCD_INITIAL_CLUSTER'] = ','.join(
            '%s=https://%s:2380' % (p['hostname'], p['hostname'])
            for p in peers)

    if hostname == genesis['hostname']:
        result['env']['ETCD_INITIAL_CLUSTER_STATE'] = 'new'
    else:
        result['env']['ETCD_INITIAL_CLUSTER_STATE'] = 'existing'

    return result


def _extract_current_node_data(nodes, hostname):
    base = nodes[hostname]
    return {
        'hostname': hostname,
        'labels': _extract_node_labels(base),
        **base,
    }


ROLE_LABELS = {
    'genesis': [
        'promenade=genesis',
    ],
    'master': [
        'node-role.kubernetes.io/master=',
    ],
}


def _extract_node_labels(data):
    labels = set(itertools.chain.from_iterable(
        map(lambda k: ROLE_LABELS.get(k, []), ['common'] + data['roles'])))
    labels.update(data.get('additional_labels', []))
    return sorted(labels)


def _extract_genesis_data(nodes):
    for hostname, node in nodes.items():
        if 'genesis' in node['roles']:
            return {
                'hostname': hostname,
                'ip': node['ip'],
            }


def _extract_master_data(nodes):
    return sorted(({'hostname': hostname, 'ip': node['ip']}
                   for hostname, node in nodes.items()
                   if 'master' in node['roles']),
                  key=itemgetter('hostname'))
