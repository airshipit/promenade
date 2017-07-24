# Getting Started

## Development

### Deployment using Vagrant

Make sure you have [Vagrant](https://vagrantup.com) and
[VirtualBox](https://www.virtualbox.org/wiki/Downloads) installed.

Generate the per-host configuration, certificates and keys to be used:

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
vagrant ssh n0 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n0.yaml'
```

Join the master nodes:

```bash
vagrant ssh n1 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n1.yaml'
vagrant ssh n2 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n2.yaml'
```

Join the worker node:

```bash
vagrant ssh n3 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n3.yaml'
```

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
PROMENADE_LOAD_IMAGE=/vagrant/promenade.tar bash /vagrant/up.sh /vagrant/path/to/node-config.yaml
```

To build the image from behind a proxy, you can:

```bash
export http_proxy=...
export no_proxy=...
docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$http_proxy --build-arg no_proxy=$no_proxy  -t promenade:local .
```

## Using Promenade Behind a Proxy

To use Promenade from behind a proxy, use the proxy settings described in the
[configuration docs](configuration.md).
