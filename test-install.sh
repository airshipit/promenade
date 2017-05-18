#!/usr/bin/env bash

set -ex

# Setup master
vagrant ssh n0 <<EOS
set -ex
sudo docker load -i /vagrant/promenade-genesis.tar
sudo docker run -v /:/target -v /var/run/docker.sock:/var/run/docker.sock -e NODE_HOSTNAME=n0 quay.io/attcomdev/promenade-genesis:dev
EOS

# Join nodes
for node in n1 n2; do
  vagrant ssh $node <<EOS
set -ex
sudo docker load -i /vagrant/promenade-join.tar
# Should be: sudo docker run -v /:/target -e NODE_HOSTNAME=$node quay.io/attcomdev/promenade-join:dev
sudo docker run -v /:/target -v /var/run/docker.sock:/var/run/docker.sock -e NODE_HOSTNAME=$node quay.io/attcomdev/promenade-join:dev
EOS
done
