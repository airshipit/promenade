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
import logging

from promenade.config import Configuration
from promenade.control import base
from promenade import exceptions
from promenade import policy
from promenade.utils.validation_message import ValidationMessage
from promenade import validation

LOG = logging.getLogger(__name__)


class ValidateDesignResource(base.BaseResource):
    @policy.ApiEnforcer('kubernetes_provisioner:post_validatedesign')
    def on_post(self, req, resp):
        result = ValidationMessage()
        try:
            json_data = self.req_json(req)
            href = json_data.get('href', None)
            config = Configuration.from_design_ref(
                href, allow_missing_substitutions=False)
            result = validation.validate_all(config)
        except exceptions.InvalidFormatError as e:
            msg = "Invalid JSON Format: %s" % str(e)
            result.add_error_message(msg, name=e.title)
        except Exception as e:
            result.add_error_message(str(e), name=e.title)

        result.update_response(resp)
