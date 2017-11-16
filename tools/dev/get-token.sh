#!/usr/bin/env bash
set -e

curl -is \
  -H "Content-Type: application/json" \
  -d '
{ "auth": {
    "identity": {
      "methods": ["password"],
      "password": {
        "user": {
          "name": "admin",
          "domain": { "id": "default" },
          "password": "password"
        }
      }
    }
  }
}' \
  http://keystone-api.ucp.svc.cluster.local/v3/auth/tokens | grep 'X-Subject-Token' | awk '{print $2}'
