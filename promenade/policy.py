# Copyright 2017 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import falcon
import functools
import oslo_policy.policy as op
from oslo_config import cfg

from promenade import exceptions as ex
from promenade import logging

LOG = logging.getLogger(__name__)

policy_engine = None

POLICIES = [
    op.RuleDefault('admin_required',
                   'role:admin or is_admin:1',
                   description='Actions requiring admin authority'),
    op.DocumentedRuleDefault('kubernetes_provisioner:get_join_scripts',
                             'role:admin', 'Get join script for node',
                             [{
                                 'path': '/api/v1.0/join-scripts',
                                 'method': 'GET'
                             }]),
    op.DocumentedRuleDefault('kubernetes_provisioner:post_validatedesign',
                             'role:admin', 'Validate documents',
                             [{
                                 'path': '/api/v1.0/validatedesign',
                                 'method': 'POST'
                             }]),
    op.DocumentedRuleDefault('kubernetes_provisioner:update_node_labels',
                             'role:admin', 'Update Node Labels',
                             [{
                                 'path': '/api/v1.0/node-labels/{node_name}',
                                 'method': 'PUT'
                             }]),
]


class PromenadePolicy:

    def __init__(self):
        self.enforcer = op.Enforcer(cfg.CONF)

    def register_policy(self):
        self.enforcer.register_defaults(POLICIES)
        self.enforcer.load_rules()

    def authorize(self, action, ctx):
        target = {'project_id': ctx.project_id, 'user_id': ctx.user_id}
        return self.enforcer.authorize(action, target, ctx.to_policy_view())


class ApiEnforcer(object):
    """
    A decorator class for enforcing RBAC policies
    """

    def __init__(self, action):
        self.action = action

    def __call__(self, f):

        @functools.wraps(f)
        def secure_handler(slf, req, resp, *args, **kwargs):
            ctx = req.context
            policy_eng = ctx.policy_engine
            # policy engine must be configured
            if policy_eng is not None:
                LOG.debug('Enforcing policy %s on request %s using engine %s',
                          self.action,
                          ctx.request_id,
                          policy_eng.__class__.__name__,
                          ctx=ctx)
            else:
                LOG.error('No policy engine configured', ctx=ctx)
                raise ex.PromenadeException(
                    title="Auth is not being handled by any policy engine",
                    status=falcon.HTTP_500,
                    retry=False)

            authorized = False
            try:
                if policy_eng.authorize(self.action, ctx):
                    LOG.debug('Request is authorized', ctx=ctx)
                    authorized = True
            except Exception:
                LOG.exception('Error authorizing request for action %s',
                              self.action,
                              ctx=ctx)
                raise ex.ApiError(title="Expectation Failed",
                                  status=falcon.HTTP_417,
                                  retry=False)

            if authorized:
                return f(slf, req, resp, *args, **kwargs)
            else:
                # raise the appropriate response exeception
                if ctx.authenticated:
                    LOG.error('Unauthorized access attempted for action %s',
                              self.action,
                              ctx=ctx)
                    raise ex.ApiError(
                        title="Forbidden",
                        status=falcon.HTTP_403,
                        description="Credentials do not permit access",
                        retry=False)
                else:
                    LOG.error('Unathenticated access attempted for action %s',
                              self.action,
                              ctx=ctx)
                    raise ex.ApiError(
                        title="Unauthenticated",
                        status=falcon.HTTP_401,
                        description="Credentials are not established",
                        retry=False)

        return secure_handler
