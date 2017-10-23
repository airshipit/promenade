registry_down() {
    REGISTRY_ID=$(docker ps -qa -f name=registry)
    if [ "x${REGISTRY_ID}" != "x" ]; then
        log Removing docker registry
        docker rm -fv ${REGISTRY_ID} &>> ${LOG_FILE}
    fi
}

registry_list_images() {
    FILES=$(find $(config_configuration) -type f -name '*.yaml')

    HOSTNAME_REGEX='[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}'
    DOMAIN_NAME_REGEX="${HOSTNAME_REGEX}(\.${HOSTNAME_REGEX})*"
    PORT_REGEX='[0-9]+'
    NETLOC_REGEX="${DOMAIN_NAME_REGEX}(:${PORT_REGEX})?"

    REPO_COMPONENT_REGEX='[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}'
    REPO_REGEX="${REPO_COMPONENT_REGEX}(/${REPO_COMPONENT_REGEX})*"

    TAG_REGEX='[a-zA-Z0-9][a-zA-Z0-9.-]{0,127}'

    cat ${FILES} \
        | tr ' \t' '\n' | tr -s '\n' \
        | grep -E "^(${NETLOC_REGEX}/)?${REPO_REGEX}:${TAG_REGEX}$" \
        | sort -u \
        | grep -v 'registry:5000'
}

registry_populate() {
    log Validating local registry is populated
    for image in $(registry_list_images); do
        if ! docker pull localhost:5000/${image} &> /dev/null; then
            log Loading image ${image} into local registry
            docker pull ${image} &>> ${LOG_FILE}
            docker tag ${image} localhost:5000/${image} &>> ${LOG_FILE}
            docker push localhost:5000/${image} &>> ${LOG_FILE}
        fi
    done
}

registry_replace_references() {
    FILES=${@}
    for image in $(registry_list_images ${FILES}); do
        sed -i "s;${image};registry:5000/${image};g" ${FILES}
    done
}

registry_up() {
    log Validating local registry is up
    REGISTRY_ID=$(docker ps -qa -f name=registry)
    RUNNING_REGISTRY_ID=$(docker ps -q -f name=registry)
    if [ "x${RUNNING_REGISTRY_ID}" = "x" -a "x${REGISTRY_ID}" != "x" ]; then
        log Removing stopped docker registry
        docker rm -fv ${REGISTRY_ID} &>> ${LOG_FILE}
    fi

    if [ "x${REGISTRY_ID}" = "x" ]; then
        log Starting docker registry
        docker run -d \
            -p 5000:5000 \
            -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
            --restart=always \
            --name registry \
            -v $REGISTRY_DATA_DIR:/var/lib/registry \
                registry:2 &>> ${LOG_FILE}
    fi
}
