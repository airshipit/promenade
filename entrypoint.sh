#!/bin/bash
set -ex

PORT=${PORT:-9000}

if [ "$1" = 'server' ]; then
    exec uwsgi \
        --http :${PORT} \
        --paste config:/etc/promenade/api-paste.ini \
        --enable-threads -L \
        --workers 4
fi

exec ${@}
