#!/bin/bash
set -ex

PORT=${PORT:-9000}
UWSGI_TIMEOUT=${UWSGI_TIMEOUT:-300}

PROMENADE_THREADS=${PROMENADE_THREADS:-1}
PROMENADE_WORKERS=${PROMENADE_WORKERS:-4}

if [ "$1" = 'server' ]; then
    exec uwsgi \
        --http ":${PORT}" \
        --http-timeout "${UWSGI_TIMEOUT}" \
        --harakiri "${UWSGI_TIMEOUT}" \
        --socket-timeout "${UWSGI_TIMEOUT}" \
        --harakiri-verbose \
        -b 32768 \
        --lazy-apps \
        --master \
        --thunder-lock \
        --die-on-term \
        --paste config:/etc/promenade/api-paste.ini \
        --enable-threads \
        --threads "${PROMENADE_THREADS}" \
        --workers "${PROMENADE_WORKERS}" \
        --logger "null file:/dev/null" \
        --log-route "null health"
fi

exec ${@}
