from oslo_config import cfg
import keystoneauth1.loading

OPTIONS = []


def setup(disable=None):
    if disable is None:
        disable = []
    else:
        disable = disable.split()

    for name, func in GROUPS.items():
        if name not in disable:
            func()

    cfg.CONF([], project='promenade')


def register_application():
    cfg.CONF.register_opts(OPTIONS)


def register_keystone_auth():
    cfg.CONF.register_opts(
        keystoneauth1.loading.get_auth_plugin_conf_options('password'),
        group='keystone_authtoken')


GROUPS = {
    'promenade': register_application,
    'keystone': register_keystone_auth,
}
