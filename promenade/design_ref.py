from . import logging
from oslo_config import cfg
import keystoneauth1.identity.v3
import keystoneauth1.session
import requests
import yaml

LOG = logging.getLogger(__name__)

__all__ = ['get_documents']

_DECKHAND_PREFIX = 'deckhand+'

DH_TIMEOUT = 10 * 60  # 10 Minute timeout for fetching from Deckhand.


def get_documents(design_ref, ctx=None):
    LOG.debug('Fetching design_ref="%s"', design_ref, ctx=ctx)
    if design_ref.startswith(_DECKHAND_PREFIX):
        response = _get_from_deckhand(design_ref, ctx)
        use_dh_engine = False
    else:
        response = _get_from_basic_web(design_ref)
        use_dh_engine = True
    LOG.debug('Got response for design_ref="%s"', design_ref, ctx=ctx)

    response.raise_for_status()

    return list(yaml.safe_load_all(response.text)), use_dh_engine


def _get_from_basic_web(design_ref):
    return requests.get(design_ref, timeout=5)


def _get_from_deckhand(design_ref, ctx=None):
    keystone_args = {}
    for attr in ('auth_url', 'password', 'project_domain_name', 'project_name',
                 'username', 'user_domain_name'):
        keystone_args[attr] = cfg.CONF.get('keystone_authtoken', {}).get(attr)
    if ctx is not None:
        addl_headers = {
            'X-CONTEXT-MARKER': ctx.context_marker,
            'X-END-USER': ctx.end_user
        }
    else:
        addl_headers = {}
    auth = keystoneauth1.identity.v3.Password(**keystone_args)
    session = keystoneauth1.session.Session(auth=auth,
                                            additional_headers=addl_headers)

    return session.get(design_ref[len(_DECKHAND_PREFIX):], timeout=DH_TIMEOUT)
