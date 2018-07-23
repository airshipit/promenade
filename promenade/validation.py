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

__all__ = ['check_schema', 'check_schemas']

LOG = logging.getLogger(__name__)


def check_design(config):
    kinds = ['Docker', 'Genesis', 'HostSystem', 'Kubelet', 'KubernetesNetwork']
    validation_msg = ValidationMessage()
    for kind in kinds:
        count = 0
        schema = None
        name = None
        for doc in config.documents:
            schema = doc.get('schema', None)
            if not schema:
                msg = '"schema" is a required document key.'
                exc = exceptions.ValidationException(msg)
                validation_msg.add_error_message(str(exc), name=exc.title)
                return validation_msg
            name = schema.split('/')[1]
            if name == kind:
                count += 1
        if count != 1:
            msg = ('There are {0} {1} documents. However, there should be one.'
                   ).format(count, kind)
            exc = exceptions.ValidationException(msg)
            validation_msg.add_error_message(
                str(exc), name=exc.title, schema=schema, doc_name=kind)
    return validation_msg


def check_schemas(documents, schemas=None):
    if not schemas:
        schemas = load_schemas_from_docs(documents)
    for document in documents:
        check_schema(document, schemas=schemas)


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
        LOG.warning('Skipping validation for unknown schema: %s', schema_name)


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
