# Getting Started

## Development

### Deployment using Vagrant

Make sure you have [Vagrant](https://vagrantup.com) and
[VirtualBox](https://www.virtualbox.org/wiki/Downloads) installed.

Generate the certificates and keys to be used:

```bash
mkdir configs
docker run --rm -t -v $(pwd):/target quay.io/attcomdev/promenade:latest promenade -v generate -c /target/example/vagrant-input-config.yaml -o /target/configs
```

Start the VMs:

```bash
vagrant up
```

Start the genesis node:

```bash
vagrant ssh n0 -c 'sudo /vagrant/up.sh /vagrant/configs/n0.yaml'
```

Join the master nodes:

```bash
vagrant ssh n1 -c 'sudo /vagrant/up.sh /vagrant/configs/n1.yaml'
vagrant ssh n2 -c 'sudo /vagrant/up.sh /vagrant/configs/n2.yaml'
```

Join the worker node:

```bash
vagrant ssh n3 -c 'sudo /vagrant/up.sh /vagrant/configs/n3.yaml'
```

### Development Cleanup

If you are testing/developing on hosts that cannot be easily destroyed, you may
find the `cleanup.sh` script useful.

### Building the image

```bash
docker build -t promenade:local .
```

For development, you may wish to save it and have the `up.sh` script load it:

```bash
docker save -o promenade.tar promenade:local
```

Then on a node:

```bash
PROMENADE_LOAD_IMAGE=/vagrant/promenade.tar /vagrant/up.sh /vagrant/path/to/node-config.yaml
```

To build the image from behind a proxy, you can:

```bash
export http_proxy=...
export no_proxy=...
docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$http_proxy --build-arg no_proxy=$no_proxy  -t promenade:local .
```

## Using Promenade Behind a Proxy

To use Promenade from behind a proxy, simply export `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables on the vagrant host prior to executing the `genesis.sh` and `join.sh` scripts respectively.  Alternatively, you may also export the `DOCKER_HTTP_PROXY`, `DOCKER_HTTPS_PROXY`, and `DOCKER_NO_PROXY` directly. Ensure you are running the script with `sudo -E` option to preserve the environment variables.

```bash
vagrant ssh n0
cd /vagrant
export DOCKER_HTTP_PROXY="http://proxy.server.com:8080"
export DOCKER_HTTPS_PROXY="https://proxy.server.com:8080"
export DOCKER_NO_PROXY="localhost,127.0.0.1"
sudo -E /vagrant/up.sh /vagrant/configs/n0.yaml
```
