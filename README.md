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

## Using Promenade Behind a Proxy

To use Promenade from behind a proxy, simply export `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables on the vagrant host prior to executing the `genesis.sh` and `join.sh` scripts respectively.  Alternatively, you may also export the `DOCKER_HTTP_PROXY`, `DOCKER_HTTPS_PROXY`, and `DOCKER_NO_PROXY` directly. Ensure you are running the script with `sudo -E` option to preserve the environment variables.

```bash
vagrant ssh n0
cd /vagrant
export DOCKER_HTTP_PROXY="http://proxy.server.com:8080"
export DOCKER_HTTPS_PROXY="https://proxy.server.com:8080"
export DOCKER_NO_PROXY="localhost,127.0.0.1"
sudo -E /vagrant/genesis.sh /vagrant/example/vagrant-config.yaml
```
