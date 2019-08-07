from oslo_config import cfg
import keystoneauth1.loading

OPTIONS = []


def setup(disable_keystone=False):
    cfg.CONF([], project='promenade')
    cfg.CONF.register_opts(OPTIONS)
    log_group = cfg.OptGroup(name='logging', title='Logging options')
    cfg.CONF.register_group(log_group)
    logging_options = [
        cfg.StrOpt(
            'log_level',
            choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
            default='DEBUG',
            help='Global log level for PROMENADE')
    ]
    cfg.CONF.register_opts(logging_options, group=log_group)
    if disable_keystone is False:
        cfg.CONF.register_opts(
            keystoneauth1.loading.get_auth_plugin_conf_options('password'),
            group='keystone_authtoken')
