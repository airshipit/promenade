#!/bin/sh

set -x

SUCCESS=1

{{/* Use built-in health check */}}
if ! wget -O - http://127.0.0.1:8080/health; then
    echo "Failed CoreDNS health check endpoint"
    SUCCESS=0
fi

{{/* Perform direct name lookups*/}}
{{- range .Values.conf.test.names_to_resolve }}
if dig +time=2 +tries=1 {{ . }} @127.0.0.1; then
    echo "Successfully resolved {{ . }}"
else
    echo "Failed to resolve {{ . }}"
    SUCCESS=0
fi
{{- end }}
if [ "$SUCCESS" != "1" ]; then
    echo "Test failed to resolve all names."
    exit 1
fi
