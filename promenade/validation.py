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
from promenade.utils.validation_message import ValidationMessage
import jsonschema
import os
import pkg_resources
import yaml

__all__ = ['check_schema', 'check_schemas', 'validate_all']

LOG = logging.getLogger(__name__)


def validate_all(config):
    """Run all available Promenade validations on the config."""

    exception_list = check_schemas(config.documents)
    exception_list.extend(check_design(config))

    validation_msg = ValidationMessage()

    for ex in exception_list:
        validation_msg.add_error_message(str(ex))

    return validation_msg


def check_design(config):
    """Check that each document type has the correct cardinality."""

    expected_count = {
        'Docker': 1,
        'Genesis': 1,
        'HostSystem': 1,
        'Kubelet': 1,
        'KubernetesNetwork': 1,
    }

    counts = {}
    exception_list = []

    for k in expected_count.keys():
        counts[k] = 0

    for doc in config.documents:
        schema = doc.get('schema', None)
        if not schema:
            msg = '"schema" is a required document key.'
            exception_list.append(exceptions.ValidationException(msg))
            continue
        name = schema.split('/')[1]
        if name in counts:
            counts[name] += 1

    for kind, cnt in counts.items():
        if cnt != 1:
            msg = ('There are {0} {1} documents. However, there should be one.'
                   ).format(cnt, kind)
            exception_list.append(exceptions.ValidationException(msg))
    return exception_list


def check_schemas(documents, schemas=None):
    if not schemas:
        schemas = load_schemas_from_docs(documents)
    exception_list = []
    for document in documents:
        try:
            check_schema(document, schemas=schemas)
        except exceptions.ValidationException as ex:
            exception_list.append(ex)
    return exception_list


def check_schema(document, schemas=None):
    if not isinstance(document, dict):
        msg = 'Non-dictionary document passed to schema validation.'
        LOG.error(msg)
        return

    schema_name = document.get('schema', '<missing>')

    LOG.debug('Validating schema for schema=%s metadata.name=%s', schema_name,
              document.get('metadata', {}).get('name', '<missing>'))

    schema_set = SCHEMAS if schemas is None else schemas

    if schema_name in schema_set:
        try:
            jsonschema.validate(document.get('data'), schema_set[schema_name])
        except jsonschema.ValidationError as e:
            raise exceptions.ValidationException(str(e))
    else:
        LOG.debug('Skipping validation for unknown schema: %s', schema_name)


SCHEMAS = {}


def load_schemas_from_docs(doc_set):
    '''
    Fills the cache of known schemas from the document set
    '''
    SCHEMA_SCHEMA = "deckhand/DataSchema/v1"

    schema_set = dict()
    for document in doc_set:
        if document.get('schema', '') == SCHEMA_SCHEMA:
            name = document['metadata']['name']
            LOG.debug("Found schema for %s." % name)
            if name in schema_set:
                raise RuntimeError('Duplicate schema specified for: %s' % name)

            schema_set[name] = document['data']

    return schema_set


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
