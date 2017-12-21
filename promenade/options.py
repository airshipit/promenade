from oslo_config import cfg
import keystoneauth1.loading

OPTIONS = []


def setup(disable_keystone=False):
    cfg.CONF([], project='promenade')
    cfg.CONF.register_opts(OPTIONS)
    if disable_keystone is False:
        cfg.CONF.register_opts(
            keystoneauth1.loading.get_auth_plugin_conf_options('password'),
            group='keystone_authtoken')
