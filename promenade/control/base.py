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
import json
import uuid

from oslo_context import context
from jsonschema import validate

import falcon
import falcon.request as request
import falcon.routing as routing

from promenade import exceptions as exc
from promenade import logging

LOG = logging.getLogger(__name__)


class BaseResource(object):
    def on_options(self, req, resp, **kwargs):
        """
        Handle options requests
        """
        method_map = routing.create_http_method_map(self)
        for method in method_map:
            if method_map.get(method).__name__ != 'method_not_allowed':
                resp.append_header('Allow', method)
        resp.status = falcon.HTTP_200

    def req_json(self, req, validate_json_schema=None):
        """
        Reads and returns the input json message, optionally validates against
        a provided jsonschema
        :param req: the falcon request object
        :param validate_json_schema: the optional jsonschema to use for
                                     validation
        """
        has_input = False
        if ((req.content_length is not None or req.content_length != 0)
                and (req.content_type is not None
                     and req.content_type.lower() == 'application/json')):
            raw_body = req.stream.read(req.content_length or 0)
            if raw_body is not None:
                has_input = True
                LOG.info('Input message body: %s \nContext: %s' %
                         (raw_body, req.context))
            else:
                LOG.info(
                    'No message body specified. \nContext: %s' % req.context)
        if has_input:
            # read the json and validate if necessary
            try:
                raw_body = raw_body.decode('utf-8')
                json_body = json.loads(raw_body)
                if validate_json_schema:
                    # raises an exception if it doesn't validate
                    validate(json_body, json.loads(validate_json_schema))
                return json_body
            except json.JSONDecodeError as jex:
                LOG.error('Invalid JSON in request: \n%s \nContext: %s' %
                          (raw_body, req.context))
                raise exc.InvalidFormatError(
                    title='JSON could not be decoded',
                    description='%s: Invalid JSON in body: %s' % (req.path,
                                                                  jex))
        else:
            # No body passed as input. Fail validation if it was asekd for
            if validate_json_schema is not None:
                raise exc.InvalidFormatError(
                    title='Json body is required',
                    description='%s: Bad input, no body provided' % (req.path))
            else:
                return None

    def to_json(self, body_dict):
        """
        Thin wrapper around json.dumps, providing the default=str config
        """
        return json.dumps(body_dict, default=str)


class PromenadeRequestContext(context.RequestContext):
    """
    Context object for promenade resource requests
    """

    def __init__(self, context_marker=None, policy_engine=None, **kwargs):
        self.log_level = 'error'
        self.request_id = str(uuid.uuid4())
        self.context_marker = context_marker
        self.policy_engine = policy_engine
        self.is_admin_project = False
        self.authenticated = False
        super(PromenadeRequestContext, self).__init__(**kwargs)

    def set_log_level(self, level):
        if level in ['error', 'info', 'debug']:
            self.log_level = level

    def set_user(self, user):
        self.user = user

    def set_project(self, project):
        self.project = project

    def add_role(self, role):
        self.roles.append(role)

    def add_roles(self, roles):
        self.roles.extend(roles)

    def remove_role(self, role):
        self.roles = [x for x in self.roles if x != role]

    def set_context_marker(self, context_marker):
        self.context_marker = context_marker

    def set_request_id(self, request_id):
        self.request_id = request_id

    def set_end_user(self, end_user):
        self.end_user = end_user

    def set_policy_engine(self, engine):
        self.policy_engine = engine

    def to_policy_view(self):
        policy_dict = {}

        policy_dict['user_id'] = self.user_id
        policy_dict['user_domain_id'] = self.user_domain_id
        policy_dict['project_id'] = self.project_id
        policy_dict['project_domain_id'] = self.project_domain_id
        policy_dict['roles'] = self.roles
        policy_dict['is_admin_project'] = self.is_admin_project

        return policy_dict

    def to_log_context(self):
        result = {}

        result['request_id'] = getattr(self, 'request_id', None)
        result['context_marker'] = getattr(self, 'context_marker', None)
        result['end_user'] = getattr(self, 'end_user', None)
        result['user'] = getattr(self, 'user', None)

        return result


class PromenadeRequest(request.Request):
    context_type = PromenadeRequestContext
