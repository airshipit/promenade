#!/bin/sh

set -x

touch /tmp/stop
sleep {{ .Values.anchor.period }}
