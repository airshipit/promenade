#!/usr/bin/env bash

set -e

{% include "utils.sh" with context %}

# Ensure the script is running as root.
#
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

function log {
    echo $(date) $* 1>&2
}
