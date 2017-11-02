nginx_down() {
    REGISTRY_ID=$(docker ps -qa -f name=promenade-nginx)
    if [ "x${REGISTRY_ID}" != "x" ]; then
        log Removing nginx server
        docker rm -fv "${REGISTRY_ID}" &>> "${LOG_FILE}"
    fi
}

nginx_up() {
    log Starting nginx server to serve configuration files
    mkdir -p "${TEMP_DIR}/nginx"
    docker run -d \
        -p 7777:80 \
        --restart=always \
        --name promenade-nginx \
        -v "${TEMP_DIR}/nginx:/usr/share/nginx/html:ro" \
            nginx:stable &>> "${LOG_FILE}"
}
