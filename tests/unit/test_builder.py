# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from promenade import builder, generator, config, encryption_method
import copy
import os
import pytest


def load_full_config(dirname):
    this_dir = os.path.dirname(os.path.realpath(__file__))
    search_dir = os.path.join(this_dir, 'builder_data', dirname)
    streams = []
    for filename in os.listdir(search_dir):
        stream = open(os.path.join(search_dir, filename))
        streams.append(stream)

    raw_config = config.Configuration.from_streams(
        allow_missing_substitutions=True,
        debug=True,
        streams=streams,
        substitute=True,
        validate=False,
    )
    g = generator.Generator(raw_config, block_strings=False)
    g.generate()

    documents = copy.deepcopy(raw_config.documents)
    documents.extend(copy.deepcopy(g.get_documents()))

    return config.Configuration(
        allow_missing_substitutions=False,
        debug=True,
        documents=documents,
        substitute=True,
        validate=True,
    )


def test_build_simple():
    b = builder.Builder(load_full_config('simple'))
    genesis_script = b.build_genesis_script()
    assert len(genesis_script) > 0

    n1_join_script = b.build_node_script('n1')
    assert len(n1_join_script) > 0
