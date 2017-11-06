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
#
import functools

import falcon

from promenade import exceptions as ex

# TODO: Add policy_engine
policy_engine = None


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
            slf.info(ctx, "Policy Engine: %s" % policy_eng.__class__.__name__)
            # perform auth
            slf.info(ctx, "Enforcing policy %s on request %s" %
                     (self.action, ctx.request_id))
            # policy engine must be configured
            if policy_eng is None:
                slf.error(
                    ctx,
                    "Error-Policy engine required-action: %s" % self.action)
                raise ex.PromenadeException(
                    title="Auth is not being handled by any policy engine",
                    status=falcon.HTTP_500,
                    retry=False)
            authorized = False
            try:
                if policy_eng.authorize(self.action, ctx):
                    # authorized
                    slf.info(ctx, "Request is authorized")
                    authorized = True
            except Exception:
                # couldn't service the auth request
                slf.error(
                    ctx,
                    "Error - Expectation Failed - action: %s" % self.action)
                raise ex.ApiError(
                    title="Expectation Failed",
                    status=falcon.HTTP_417,
                    retry=False)
            if authorized:
                return f(slf, req, resp, *args, **kwargs)
            else:
                slf.error(
                    ctx,
                    "Auth check failed. Authenticated:%s" % ctx.authenticated)
                # raise the appropriate response exeception
                if ctx.authenticated:
                    slf.error(
                        ctx,
                        "Error: Forbidden access - action: %s" % self.action)
                    raise ex.ApiError(
                        title="Forbidden",
                        status=falcon.HTTP_403,
                        description="Credentials do not permit access",
                        retry=False)
                else:
                    slf.error(ctx, "Error - Unauthenticated access")
                    raise ex.ApiError(
                        title="Unauthenticated",
                        status=falcon.HTTP_401,
                        description="Credentials are not established",
                        retry=False)

        return secure_handler
