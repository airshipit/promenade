Getting Started
===============

Development
-----------

Deployment using Vagrant
^^^^^^^^^^^^^^^^^^^^^^^^

Deployment using Vagrant uses KVM instead of Virtualbox due to better
performance of disk and networking, which both have significant impact on the
stability of the etcd clusters.

Make sure you have [Vagrant](https://vagrantup.com) installed, then
run `./tools/full-vagrant-setup.sh`, which will do the following:

* Install Vagrant libvirt plugin and its dependencies
* Install NFS dependencies for Vagrant volume sharing
* Install [packer](https://packer.io) and build a KVM image for Ubuntu 16.04

Generate the per-host configuration, certificates and keys to be used:

.. code-block:: bash

    mkdir configs
    docker run --rm -t -v $(pwd):/target quay.io/attcomdev/promenade:latest promenade -v generate -c /target/example/vagrant-input-config.yaml -o /target/configs


Start the VMs:

.. code-block:: bash

    vagrant up

Start the genesis node:

.. code-block:: bash

    vagrant ssh n0 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n0.yaml'

Join the master nodes:

.. code-block:: bash

    vagrant ssh n1 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n1.yaml'
    vagrant ssh n2 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n2.yaml'

Join the worker node:

.. code-block:: bash

    vagrant ssh n3 -c 'sudo bash /vagrant/configs/up.sh /vagrant/configs/n3.yaml'

Building the image
^^^^^^^^^^^^^^^^^^

.. code-block:: bash

    docker build -t promenade:local .


For development, you may wish to save it and have the `up.sh` script load it:

.. code-block:: bash

    docker save -o promenade.tar promenade:local


Then on a node:

.. code-block:: bash

    PROMENADE_LOAD_IMAGE=/vagrant/promenade.tar bash /vagrant/up.sh /vagrant/path/to/node-config.yaml


These commands are combined in a convenience script at `tools/dev-build.sh`.

To build the image from behind a proxy, you can:

.. code-block:: bash

    export http_proxy=...
    export no_proxy=...
    docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$http_proxy --build-arg no_proxy=$no_proxy  -t promenade:local .


Using Promenade Behind a Proxy
------------------------------

To use Promenade from behind a proxy, use the proxy settings described in the
[configuration docs](configuration.md).
