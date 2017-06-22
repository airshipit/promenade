#!/usr/bin/env bash

set -x

systemctl stop kubelet
docker rm -fv $(docker ps -aq)

systemctl stop docker

apt-get remove -qq -y dnsmasq

systemctl daemon-reload

rm -rf \
    /etc/dnsmasq.d/kubernetes-masters \
    /etc/docker \
    /etc/kubernetes \
    /etc/systemd/system/docker.service.d \
    /etc/systemd/system/kubelet \
    /opt/cni \
    /usr/local/bin/bootstrap \
    /usr/local/bin/helm \
    /usr/local/bin/kubectl \
    /usr/local/bin/kubelet \
    /var/lib/auxiliary-etcd-0 \
    /var/lib/auxiliary-etcd-1 \
    /var/lib/kube-etcd \
    /var/lib/prom.done
