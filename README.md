# Overview

Promenade is tool for deploying self-hosted, highly resilient Kubernetes clusters.

## Quickstart using Vagrant

Make sure you have [Vagrant](https://vagrantup.com) and
[VirtualBox](https://www.virtualbox.org/wiki/Downloads) installed.

Start the VMs:

```bash
vagrant up
```

Start the genesis node:

```bash
vagrant ssh n0 -c 'sudo /vagrant/genesis.sh /vagrant/example/vagrant-config.yaml'
```

Join the master nodes:

```bash
vagrant ssh n1 -c 'sudo /vagrant/join.sh /vagrant/example/vagrant-config.yaml'
vagrant ssh n2 -c 'sudo /vagrant/join.sh /vagrant/example/vagrant-config.yaml'
```

Join the worker node:

```bash
vagrant ssh n3 -c 'sudo /vagrant/join.sh /vagrant/example/vagrant-config.yaml'
```

## Building the image

```bash
docker build -t quay.io/attcomdev/promenade:experimental .
```
