# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
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
import json

from promenade.utils.message import Message


class ValidationMessage(Message):
    """ ValidationMessage per UCP convention:
    https://github.com/att-comdev/ucp-integration/blob/master/docs/source/api-conventions.rst#output-structure  # noqa

    Construction of ValidationMessage message:

    :param string message: Validation failure message.
    :param boolean error: True or False, if this is an error message.
    :param string name: Identifying name of the validation.
    :param string level: The severity of validation result, as "Error",
        "Warning", or "Info"
    :param string schema: The schema of the document being validated.
    :param string doc_name: The name of the document being validated.
    :param string diagnostic: Information about what lead to the message,
        or details for resolution.
    """

    def __init__(self):
        super(ValidationMessage, self).__init__()
        self.output.update({'reason': 'Validation'})

    def add_error_message(self,
                          msg,
                          name=None,
                          schema=None,
                          doc_name=None,
                          diagnostic=None):
        new_error = {
            'message': msg,
            'error': True,
            'name': name,
            'documents': [],
            'level': "Error",
            'diagnostic': diagnostic,
            'kind': 'ValidationMessage'
        }
        if schema and doc_name:
            new_error['documents'].append(dict(schema=schema, name=doc_name))
        self.details['errorCount'] += 1
        self.details['messageList'].append(new_error)

    def get_output(self, code=falcon.HTTP_400):
        """ Return ValidationMessage message.

        :returns: The ValidationMessage for the Validation API response.
        :rtype: dict
        """
        if self.details['errorCount'] != 0:
            self.output['code'] = code
            self.output['message'] = 'Promenade validations failed'
            self.output['status'] = 'Failure'
        else:
            self.output['code'] = falcon.HTTP_200
            self.output['message'] = 'Promenade validations succeeded'
            self.output['status'] = 'Success'
        return self.output

    def update_response(self, resp):
        output = self.get_output()
        resp.status = output['code']
        resp.body = json.dumps(output)
