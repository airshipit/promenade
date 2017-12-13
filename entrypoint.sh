#!/bin/bash
set -ex

PORT=${PORT:-9000}
UWSGI_TIMEOUT=${UWSGI_TIMEOUT:-300}

if [ "$1" = 'server' ]; then
    exec uwsgi \
        --http :${PORT} \
        --http-timeout ${UWSGI_TIMEOUT} \
        -z ${UWSGI_TIMEOUT} \
        --paste config:/etc/promenade/api-paste.ini \
        --enable-threads -L \
        --workers 4
fi

exec ${@}
