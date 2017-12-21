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
from promenade.control import api
from promenade import options
from promenade import logging
from promenade import policy


def start_promenade(disable=False):
    options.setup(disable_keystone=disable)

    # Setup root logger
    logging.setup(verbose=True)

    # Setup policy
    policy.policy_engine = policy.PromenadePolicy()
    policy.policy_engine.register_policy()

    # Start the API
    return api.start_api()


# Initialization compatible with PasteDeploy
def paste_start_promenade(global_conf, **kwargs):
    return start_promenade(**kwargs)
