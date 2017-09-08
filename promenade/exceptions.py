import logging

LOG = logging.getLogger(__name__)


class PromenadeException(Exception):
    EXIT_CODE = 1

    def __init__(self, message, *, trace=True):
        self.message = message
        self.trace = trace

    def display(self, debug=False):
        if self.trace or debug:
            LOG.exception(self.message)
        else:
            LOG.error(self.message)


class ValidationException(PromenadeException):
    pass
