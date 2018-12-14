import copy
import logging
import logging.config

__all__ = ['getLogger', 'setup']

LOG_FORMAT = '%(asctime)s %(levelname)-8s %(request_id)s %(external_id)s %(user)s %(name)s:%(filename)s:%(lineno)3d:%(funcName)s %(message)s'  # noqa

BLANK_CONTEXT_VALUES = [
    'external_id',
    'request_id',
    'user',
]

DEFAULT_CONFIG = {
    'version': 1,
    'disable_existing_loggers': True,
    'filters': {
        'blank_context': {
            '()': 'promenade.logging.BlankContextFilter',
        },
    },
    'formatters': {
        'standard': {
            'format': LOG_FORMAT,
        },
    },
    'handlers': {
        'default': {
            'level': 'DEBUG',
            'formatter': 'standard',
            'class': 'logging.StreamHandler',
            'filters': ['blank_context'],
        },
    },
    'loggers': {
        'deckhand': {
            'handlers': ['default'],
            'level': 'INFO',
            'propagate': False,
        },
        'promenade': {
            'handlers': ['default'],
            'level': 'INFO',
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['default'],
        'level': 'INFO',
    },
}


class BlankContextFilter(logging.Filter):
    def filter(self, record):
        for key in BLANK_CONTEXT_VALUES:
            if getattr(record, key, None) is None:
                setattr(record, key, '-')
        return True


class Adapter(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        extra = kwargs.get('extra', {})

        ctx = kwargs.pop('ctx', None)
        if ctx is not None:
            extra.update(ctx.to_log_context())

        kwargs['extra'] = extra

        return msg, kwargs


def setup(*, verbose):
    log_config = copy.deepcopy(DEFAULT_CONFIG)
    if verbose:
        log_config['loggers']['promenade']['level'] = 'DEBUG'

    logging.config.dictConfig(log_config)


def getLogger(*args, **kwargs):
    return Adapter(logging.getLogger(*args, **kwargs), {})
