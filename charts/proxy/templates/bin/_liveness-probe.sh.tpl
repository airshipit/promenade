#!/bin/bash

set -e

IPTS_DIR=/tmp/liveness

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

mkdir -p "${IPTS_DIR}"
iptables-save {{- if .Values.livenessProbe.whitelist }} | grep -Ev "${WHITELIST}" {{- end }} | grep -s 'has no endpoints' | sort > "${IPTS_DIR}/current"

if [[ $(wc -l "${IPTS_DIR}/current") -gt 0 ]]; then
    if [[ "${IPTS_DIR}/previous" ]]; then
        if cmp "${IPTS_DIR}/current" "${IPTS_DIR}/previous"; then
            echo Some non-whitelisted services have no endpoints:
            cat "${IPTS_DIR}/current"
            FAILURE=1
        else
            echo Detected issues have changed.  Passing check:
            diff "${IPTS_DIR}/previous" "${IPTS_DIR}/current"
        fi
    fi
fi

mv "${IPTS_DIR}/current" "${IPTS_DIR}/previous"

IPTABLES_IPS=$(iptables-save | grep -E 'KUBE-SEP.*to-destination' | sed 's/.*to-destination \(.*\):.*/\1/' | sort -u)
KUBECTL_IPS=$(kubectl get --all-namespaces -o json endpoints | jq -r '.items | arrays | .[] | objects | .subsets | arrays | .[] | objects | .addresses | arrays | .[] | objects | .ip' | sort -u)

if [[ $(comm -23 <(echo "${IPTABLES_IPS}") <(echo "${KUBECTL_IPS}")) ]]; then
    FAILURE=1
    echo "Found non-current Pod IPs in iptables rules:"
    comm -23 <(echo "${IPTABLES_IPS}") <(echo "${KUBECTL_IPS}")
fi

if [[ "${FAILURE}" == "1" ]]; then
    exit 1
fi
