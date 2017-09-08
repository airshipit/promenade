Getting Started
===============

Development
-----------

Deployment using Vagrant
^^^^^^^^^^^^^^^^^^^^^^^^

Initial Setup of Vagrant
~~~~~~~~~~~~~~~~~~~~~~~~

Deployment using Vagrant uses KVM instead of Virtualbox due to better
performance of disk and networking, which both have significant impact on the
stability of the etcd clusters.

Make sure you have [Vagrant](https://vagrantup.com) installed, then
run `./tools/vagrant/full-vagrant-setup.sh`, which will do the following:

* Install Vagrant libvirt plugin and its dependencies
* Install NFS dependencies for Vagrant volume sharing
* Install [packer](https://packer.io) and build a KVM image for Ubuntu 16.04

Deployment
~~~~~~~~~~
A complete set of configuration that works with the `Vagrantfile` in the
top-level directory is provided in the `example` directory.

To exercise that example, first generate certs and combine the configuration
into usable parts:

.. code-block:: bash

    ./tools/build-example.sh

Start the VMs:

.. code-block:: bash

    vagrant up --parallel

Then bring up the genesis node:

.. code-block:: bash

    vagrant ssh n0 -c 'sudo /vagrant/example/scripts/genesis.sh'

Join additional master nodes:

.. code-block:: bash

    vagrant ssh n1 -c 'sudo /vagrant/example/scripts/join-n1.sh'
    vagrant ssh n2 -c 'sudo /vagrant/example/scripts/join-n2.sh'

Re-provision the genesis node as a normal master:

.. code-block:: bash

    vagrant ssh n0 -c 'sudo promenade-teardown'
    vagrant ssh n1 -c 'sudo kubectl delete node n0'
    vagrant destroy -f n0
    vagrant up n0
    vagrant ssh n0 -c 'sudo /vagrant/example/scripts/join-n0.sh'

Join the remaining worker:

.. code-block:: bash

    vagrant ssh n3 -c 'sudo /vagrant/example/scripts/join-n3.sh'


Building the image
^^^^^^^^^^^^^^^^^^

To build the image directly, you can use the standard Docker build command:

.. code-block:: bash

    docker build -t promenade:local .

To build the image from behind a proxy, you can:

.. code-block:: bash

    export http_proxy=...
    export no_proxy=...
    docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$http_proxy --build-arg no_proxy=$no_proxy  -t promenade:local .


For convenience, there is a script which builds an image from the current code,
then uses it to construct scripts for the example:

.. code-block:: bash

    ./tools/dev-build.sh

*NOTE* the ``dev-build.sh`` script puts Promenade in debug mode, which will
instruct it to use Vagrant's shared directory to source local charts.


Using Promenade Behind a Proxy
------------------------------

To use Promenade from behind a proxy, use the proxy settings see
:doc:`configuration/kubernetes-network`.
