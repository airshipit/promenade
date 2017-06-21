#!/usr/bin/env bash

set -x

systemctl stop kubelet
docker rm -fv $(docker ps -aq)
rm -rf /etc/kubernetes

systemctl stop docker
rm -rf /etc/docker

apt-get remote -qq -y dnsmasq
rm /etc/dnsmasq.d/kubernetes-masters

rm /etc/systemd/system/kubelet.service
systemctl daemon-reload

rm -rf /var/lib/kube-etcd
