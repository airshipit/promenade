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

import uuid

from promenade import logging
from promenade import policy

LOG = logging.getLogger('promenade')


class AuthMiddleware(object):
    # Authentication
    def process_request(self, req, resp):
        ctx = req.context
        ctx.set_policy_engine(policy.policy_engine)

        for k, v in req.headers.items():
            LOG.debug("Request with header %s: %s" % (k, v))

        auth_status = req.get_header(
            'X-SERVICE-IDENTITY-STATUS')  # will be set to Confirmed or Invalid
        service = True

        if auth_status is None:
            auth_status = req.get_header('X-IDENTITY-STATUS')
            service = False

        if auth_status == 'Confirmed':
            # Process account and roles
            ctx.authenticated = True
            # User Identity, unique within owning domain
            ctx.user = req.get_header(
                'X-SERVICE-USER-NAME') if service else req.get_header(
                    'X-USER-NAME')
            # Identity-service managed unique identifier
            ctx.user_id = req.get_header(
                'X-SERVICE-USER-ID') if service else req.get_header(
                    'X-USER-ID')
            # Identity service managed unique identifier of owning domain of
            #  user name
            ctx.user_domain_id = req.get_header(
                'X-SERVICE-USER-DOMAIN-ID') if service else req.get_header(
                    'X-USER-DOMAIN-ID')
            # Identity service managed unique identifier
            ctx.project_id = req.get_header(
                'X-SERVICE-PROJECT-ID') if service else req.get_header(
                    'X-PROJECT-ID')
            # Name of owning domain of project
            ctx.project_domain_id = req.get_header(
                'X-SERVICE-PROJECT-DOMAIN-ID') if service else req.get_header(
                    'X-PROJECT-DOMAIN-NAME')
            if service:
                # comma delimieted list of case-sensitive role names
                if req.get_header('X-SERVICE-ROLES'):
                    ctx.add_roles(req.get_header('X-SERVICE-ROLES').split(','))
            else:
                if req.get_header('X-ROLES'):
                    ctx.add_roles(req.get_header('X-ROLES').split(','))

            if req.get_header('X-IS-ADMIN-PROJECT') == 'True':
                ctx.is_admin_project = True
            else:
                ctx.is_admin_project = False

            LOG.debug('Request from authenticated user %s with roles %s',
                      ctx.user, ctx.roles)
        else:
            ctx.authenticated = False


class ContextMiddleware(object):
    """
    Handle looking at the X-Context_Marker to see if it has value and that
    value is a UUID (or close enough). If not, generate one.
    """

    def _format_uuid_string(self, string):
        return (string.replace('urn:', '').replace('uuid:', '').strip('{}')
                .replace('-', '').lower())

    def _is_uuid_like(self, val):
        try:
            return str(uuid.UUID(val)).replace(
                '-', '') == self._format_uuid_string(val)
        except (TypeError, ValueError, AttributeError):
            return False

    def process_request(self, req, resp):
        ctx = req.context
        ext_marker = req.get_header('X-Context-Marker')
        if ext_marker is not None and self._is_uuid_like(ext_marker):
            # external passed in an ok context marker
            ctx.set_external_marker(ext_marker)
        else:
            # use the request id
            ctx.set_external_marker(ctx.request_id)


class LoggingMiddleware(object):
    def process_response(self, req, resp, resource, req_succeeded):
        ctx = req.context

        resp.append_header('X-Promenade-Req', ctx.request_id)
        LOG.info('%s %s - %s', req.method, req.uri, resp.status, ctx=ctx)


class NoAuthFilter(object):
    """PasteDeploy filter for NoAuth to be used in testing."""

    def __init__(self, app, forged_roles):
        self.app = app
        self.forged_roles = forged_roles

    def __call__(self, environ, start_response):
        """Forge headers to make unauthenticated requests look authenticated.

        If the request has a X-AUTH-TOKEN header, assume it is a valid request
        and noop. Otherwise forge Keystone middleware headers so the request
        looks valid with the configured forged roles.
        """
        if 'HTTP_X_AUTH_TOKEN' in environ:
            return self.app(environ, start_response)

        environ['HTTP_X_IDENTITY_STATUS'] = 'Confirmed'

        for envvar in [
                'USER_NAME', 'USER_ID', 'USER_DOMAIN_ID', 'PROJECT_ID',
                'PROJECT_DOMAIN_NAME'
        ]:
            varname = "HTTP_X_%s" % envvar
            environ[varname] = 'noauth'

        if self.forged_roles:
            if 'admin' in self.forged_roles:
                environ['HTTP_X_IS_ADMIN_PROJECT'] = 'True'
            else:
                environ['HTTP_X_IS_ADMIN_PROJECT'] = 'False'
            environ['HTTP_X_ROLES'] = ','.join(self.forged_roles)
        else:
            environ['HTTP_X_IS_ADMIN_PROJECT'] = 'True'
            environ['HTTP_X_ROLES'] = 'admin'

        return self.app(environ, start_response)


def noauth_filter_factory(global_conf, forged_roles):
    """Create a NoAuth paste deploy filter

    :param forged_roles: A space seperated list for roles to forge on requests
    """
    forged_roles = forged_roles.split()

    def filter(app):
        return NoAuthFilter(app, forged_roles)

    return filter
