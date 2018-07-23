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

from promenade.utils.message import Message


class SuccessMessage(Message):
    """SuccessMessage per UCP convention:
    https://airshipit.readthedocs.io/en/latest/api-conventions.html#status-responses
    """

    def __init__(self, reason='', code=falcon.HTTP_200):
        super(SuccessMessage, self).__init__()
        self.output.update({
            'status': 'Success',
            'message': '',
            'reason': reason,
            'code': code
        })
