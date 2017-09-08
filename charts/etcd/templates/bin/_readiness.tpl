#!/bin/sh

set -ex

export ETCDCTL_ENDPOINTS=https://$POD_IP:{{ .Values.service.client.target_port }}

etcdctl endpoint health
