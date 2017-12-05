os_ks_get_token() {
    VIA=${1}
    KEYSTONE_URL=${2:-http://keystone-api.ucp.svc.cluster.local}
    DOMAIN=${3:-default}
    USERNAME=${4:-promenade}
    PASSWORD=${5:-password}

    REQUEST_BODY_PATH="ks-token-request.json"
    cat <<EOBODY > "${TEMP_DIR}/${REQUEST_BODY_PATH}"
{
    "auth": {
    "identity": {
      "methods": ["password"],
      "password": {
        "user": {
          "name": "${USERNAME}",
          "domain": { "id": "${DOMAIN}" },
          "password": "${PASSWORD}"
        }
      }
    }
  }
}
EOBODY

    rsync_cmd "${TEMP_DIR}/${REQUEST_BODY_PATH}" "${VIA}:/root/${REQUEST_BODY_PATH}"

    ssh_cmd "${VIA}" curl -isS \
      -H 'Content-Type: application/json' \
      -d "@/root/${REQUEST_BODY_PATH}" \
      "${KEYSTONE_URL}/v3/auth/tokens" | grep 'X-Subject-Token' | awk '{print $2}' | sed "s;';;g" | sed "s;\r;;g"
}
