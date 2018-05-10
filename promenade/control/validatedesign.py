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
import logging

import falcon

from promenade.config import Configuration
from promenade.control import base
from promenade import exceptions
from promenade import policy
from promenade import validation

LOG = logging.getLogger(__name__)


class ValidateDesignResource(base.BaseResource):
    def _return_msg(self, resp, result):
        if result['err_count'] == 0:
            message = "Promenade validations succeeded."
            status_code = falcon.HTTP_200
            status = "Success"
        else:
            message = "Promenade validations failed."
            status_code = falcon.HTTP_400
            status = "Failure"
        resp.body = json.dumps({
            "kind": "Status",
            "apiVersion": "v1",
            "metadata": {},
            "status": status,
            "message": message,
            "reason": "Validation",
            "details": {
                "errorCount": result['err_count'],
                "messageList": result['msg'],
            },
            "code": status_code,
        })

    @policy.ApiEnforcer('kubernetes_provisioner:post_validatedesign')
    def on_post(self, req, resp):

        try:
            json_data = self.req_json(req)
            href = json_data.get('href', None)
            config = Configuration.from_design_ref(
                href, allow_missing_substitutions=False)
            result = validation.check_design(config)
        except exceptions.InvalidFormatError as e:
            msg = "Invalid JSON Format: %s" % str(e)
            result = {'msg': [msg], 'err_count': 1}
        except exceptions.DeckhandException as e:
            result = {'msg': [str(e)], 'err_count': 1}
        return self._return_msg(resp, result)
