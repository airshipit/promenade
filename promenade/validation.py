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

from promenade import exceptions
from promenade import logging
import jsonschema
import os
import pkg_resources
import yaml

__all__ = ['check_schema', 'check_schemas']

LOG = logging.getLogger(__name__)


def check_schemas(documents):
    for document in documents:
        check_schema(document)


def check_schema(document):
    if type(document) != dict:
        LOG.error('Non-dictionary document passed to schema validation.')
        return

    schema_name = document.get('schema', '<missing>')

    LOG.debug('Validating schema for schema=%s metadata.name=%s', schema_name,
              document.get('metadata', {}).get('name', '<missing>'))

    if schema_name in SCHEMAS:
        try:
            jsonschema.validate(document.get('data'), SCHEMAS[schema_name])
        except jsonschema.ValidationError as e:
            raise exceptions.ValidationException(str(e))
    else:
        LOG.warning('Skipping validation for unknown schema: %s', schema_name)


SCHEMAS = {}


def _load_schemas():
    '''
    Fills the cache of known schemas
    '''
    schema_dir = _get_schema_dir()
    for schema_file in os.listdir(schema_dir):
        with open(os.path.join(schema_dir, schema_file)) as f:
            for schema in yaml.safe_load_all(f):
                name = schema['metadata']['name']
                if name in SCHEMAS:
                    raise RuntimeError(
                        'Duplicate schema specified for: %s' % name)

                SCHEMAS[name] = schema['data']


def _get_schema_dir():
    return pkg_resources.resource_filename('promenade', 'schemas')


# Fill the cache
_load_schemas()
