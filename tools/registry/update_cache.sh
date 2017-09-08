#!/usr/bin/env bash

set -ex

IMAGES_FILE=$(dirname $0)/IMAGES

IFS=,
grep -v '^#.*' $IMAGES_FILE | while read src tag dst; do
    echo src=$src tag=$tag dst=$dst
    sudo docker pull $src:$tag

    full_dst=localhost:5000/$dst:$tag
    sudo docker tag $src:$tag $full_dst

    sudo docker push $full_dst
done
