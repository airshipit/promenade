#!/usr/bin/env bash

set -ex

IMAGES_FILE=$(dirname $0)/IMAGES

IFS=,
grep -v '^#.*' $IMAGES_FILE | while read src tag dst; do
    sed -i "s;$src:$tag;registry:5000/$dst:$tag;g" example/*.yaml
done
