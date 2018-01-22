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
from promenade import logging
import traceback

import falcon

LOG = logging.getLogger(__name__)


# Standard error handler
def format_error_resp(req,
                      resp,
                      status_code,
                      message="",
                      reason="",
                      error_type=None,
                      retry=False,
                      error_list=None,
                      info_list=None):
    """
    Write a error message body and throw a Falcon exception to trigger
    an HTTP status
    :param req: Falcon request object
    :param resp: Falcon response object to update
    :param status_code: Falcon status_code constant
    :param message: Optional error message to include in the body.
                    This should be the summary level of the error
                    message, encompassing an overall result. If
                    no other messages are passed in the error_list,
                    this message will be repeated in a generated
                    message for the output message_list.
    :param reason: Optional reason code to include in the body
    :param error_type: If specified, the error type will be used,
                       otherwise, this will be set to
                       'Unspecified Exception'
    :param retry: Optional flag whether client should retry the operation.
    :param error_list: optional list of error dictionaries. Minimally,
                       the dictionary will contain the 'message' field,
                       but should also contain 'error': True
    :param info_list: optional list of info message dictionaries.
                      Minimally, the dictionary needs to contain a
                      'message' field, but should also have a
                      'error': False field.
    """

    if error_type is None:
        error_type = 'Unspecified Exception'

    # since we're handling errors here, if error list is none, set
    # up a default error item. If we have info items, add them to the
    # message list as well.  In both cases, if the error flag is not
    # set, set it appropriately.
    if error_list is None:
        error_list = [{
            'message': 'An error ocurred, but was not specified',
            'error': True
        }]
    else:
        for error_item in error_list:
            if 'error' not in error_item:
                error_item['error'] = True

    if info_list is None:
        info_list = []
    else:
        for info_item in info_list:
            if 'error' not in info_item:
                info_item['error'] = False

    message_list = error_list + info_list

    version = 'N/A'

    for part in req.path.split('/'):
        if '.' in part and part.startswith('v'):
            version = part
            break

    error_response = {
        'kind': 'status',
        'apiVersion': version,
        'metadata': {},
        'status': 'Failure',
        'message': message,
        'reason': reason,
        'details': {
            'errorType': error_type,
            'errorCount': len(error_list),
            'messageList': message_list
        },
        'code': status_code,
        'retry': retry
    }

    resp.body = json.dumps(error_response, default=str)
    resp.content_type = 'application/json'
    resp.status = status_code


def default_error_serializer(req, resp, exception):
    """
    Writes the default error message body, when we don't handle it otherwise
    """
    format_error_resp(
        req,
        resp,
        status_code=exception.status,
        message=exception.description,
        reason=exception.title,
        error_type=exception.__class__.__name__,
        error_list=[{
            'message': exception.description,
            'error': True
        }],
        info_list=None)


def default_exception_handler(ex, req, resp, params):
    """
    Catch-all exception handler for standardized output.
    If this is a standard falcon HTTPError, rethrow it for handling
    """
    if isinstance(ex, falcon.HTTPError):
        # allow the falcon http errors to bubble up and get handled
        raise ex
    else:
        # take care of the uncaught stuff
        exc_string = traceback.format_exc()
        LOG.error('Unhanded Exception being handled: \n%s', exc_string)
        format_error_resp(
            req,
            resp,
            falcon.HTTP_500,
            error_type=ex.__class__.__name__,
            message="Unhandled Exception raised: %s" % str(ex),
            retry=True)


class PromenadeException(Exception):
    """
    Base error containing enough information to make a promenade-formatted
    error
    """
    EXIT_CODE = 1

    def __init__(self,
                 title=None,
                 description=None,
                 error_list=None,
                 info_list=None,
                 status=None,
                 retry=False,
                 trace=False):
        """
        :param description: The internal error description
        :param error_list: The list of errors
        :param status: The desired falcon HTTP response code
        :param title: The title of the error message
        :param error_list: A list of errors to be included in output
                           messages list
        :param info_list: A list of informational messages to be
                          included in the output messages list
        :param retry: Optional retry directive for the consumer
        :param trace: Return traceback
        """

        self.title = title or self.__class__.title

        self.status = status or self.__class__.status

        self.description = description
        self.error_list = massage_error_list(error_list, description)
        self.info_list = info_list
        self.retry = retry
        self.trace = trace
        super().__init__(
            PromenadeException._gen_ex_message(title, description))

    @staticmethod
    def _gen_ex_message(title, description):
        ttl = title or 'Exception'
        dsc = description or 'No additional decsription'
        return '{} : {}'.format(ttl, dsc)

    @staticmethod
    def handle(ex, req, resp, params):
        """
        The handler used for app errors and child classes
        """
        format_error_resp(
            req,
            resp,
            ex.status,
            message=ex.title,
            reason=ex.description,
            error_list=ex.error_list,
            info_list=ex.info_list,
            error_type=ex.__class__.__name__,
            retry=ex.retry)

    def display(self, debug=False):
        if self.trace or debug:
            LOG.exception(self.description)
        else:
            LOG.error(self.title + (self.description or ''))


class ApiError(PromenadeException):
    """
    An error to handle general api errors.
    """

    title = 'Api Error'
    status = falcon.HTTP_400


class InvalidFormatError(PromenadeException):
    """
    An exception to cover invalid input formatting
    """

    title = 'Invalid Input Error'
    status = falcon.HTTP_400


class ValidationException(PromenadeException):
    title = 'Validation Error'
    status = falcon.HTTP_400


def massage_error_list(error_list, placeholder_description):
    """
    Returns a best-effort attempt to make a nice error list
    """
    output_error_list = []
    if error_list:
        for error in error_list:
            if not error.get('message'):
                output_error_list.append({'message': error, 'error': True})
            else:
                if 'error' not in error:
                    error['error'] = True
                output_error_list.append(error)
    if not output_error_list:
        output_error_list.append({'message': placeholder_description})
    return output_error_list
