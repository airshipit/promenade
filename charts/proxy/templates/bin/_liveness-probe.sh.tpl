#!/bin/bash

set -e

FAILURE=0
{{- if .Values.livenessProbe.whitelist }}
WHITELIST='({{- join "|" .Values.livenessProbe.whitelist -}})'
{{- end }}

REQUEST='GET /healthz HTTP/1.0\r\nHost: localhost:10256\r\n'

if [[ $(echo -e "${REQUEST}" | socat - TCP4:localhost:10256 | grep -sc '200 OK') -lt 1 ]]; then
    echo Failed proxy built-in HTTP health check.
    echo -e "${REQUEST}" | socat - TCP4:localhost:10256
    FAILURE=1
fi

if [[ $(iptables-save {{- if .Values.livenessProbe.whitelist }} | grep -Ev "${WHITELIST}" {{- end }} | grep -sc 'has no endpoints') -gt 0 ]]; then
    echo Some non-whitelisted services have no endpoints:
    iptables-save | grep 'has no endpoints'
    FAILURE=1
fi

if [[ "${FAILURE}" == "1" ]]; then
    exit 1
fi
