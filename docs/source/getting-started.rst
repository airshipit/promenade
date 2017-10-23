Getting Started
===============

Basic Deployment
----------------

Setup
^^^^^

To create the certificates and scripts needed to perform a basic deployment,
you can use the following helper script:

.. code-block:: bash

    ./tools/basic-deployment.sh examples/basic build

This will copy the configuration provided in the ``examples/basic`` directory
into the ``build`` directory.  Then, it will generate self-signed certificates
for all the needed components in Deckhand-compatible format.  Finally, it will
render the provided configuration into directly-usable ``genesis.sh`` and
``join-<NODE>.sh`` scripts.

Execution
^^^^^^^^^

Perform the following steps to execute the deployment:

1. Copy the ``genesis.sh`` script to the genesis node and run it.
2. Validate the genesis node by running ``validate-genesis.sh`` on it.
3. Join master nodes by copying their respective ``join-<NODE>.sh`` scripts to
   them and running them.
4. Validate the master nodes by copying and running their respective
   ``validate-<NODE>.sh`` scripts on each of them.
5. Re-provision the Genesis node

   a) Run the ``/usr/local/bin/promenade-teardown`` script on the Genesis node:
   b) Delete the node from the cluster via one of the other nodes ``kubectl delete node <GENESIS>``.
   c) Power off and re-image the Genesis node.
   d) Join the genesis node as a normal node using its ``join-<GENESIS>.sh`` script.
   e) Validate the node using ``validate-<GENSIS>.sh``.

6. Join and validate all remaining nodes using the ``join-<NODE>.sh`` and
   ``validate-<NODE>.sh`` scripts described above.


Running Tests
-------------

Initial Setup of Virsh Environment
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To setup a local functional testing environment on your Ubuntu 16.04 machine,
run:

.. code-block:: bash

    ./tools/setup_gate.sh

Running Functional Tests
^^^^^^^^^^^^^^^^^^^^^^^^

To run complete functional tests locally:

.. code-block:: bash

    ./tools/gate.sh

For more verbose output, try:

.. code-block:: bash

    PROMENADE_DEBUG=1 ./tools/gate.sh

For extremely verbose output, try:

.. code-block:: bash

    GATE_DEBUG=1 PROMENADE_DEBUG=1 ./tools/gate.sh

The gate leaves its test VMs running for convenience.  To shut everything down:

.. code-block:: bash

    ./tools/stop_gate.sh

To run a particular set of functional tests, you can specify the set on the
command line:

.. code-block:: bash

    ./tools/gate.sh <SUITE>

Valid functional test suites are defined by JSON files that live in
``tools/g2/manifests``.

Utilities
^^^^^^^^^

There are a couple of helper utilities available for interacting with gate VMs.
These can be found in ``tools/g2/bin``.  The most important is certainly
``ssh.sh``, which allows you to connect easily to test VMs:

.. code-block:: bash

    ./tools/g2/bin/ssh.sh n0


Development
-----------

Using a Local Registry
^^^^^^^^^^^^^^^^^^^^^^

Repeatedly downloading multiple copies images during development can be quite
slow.  To avoid this issue, you can run a docker registry on the development
host:

.. code-block:: bash

    ./tools/registry/start.sh
    ./tools/registry/update_cache.sh

Then, the images used by the basic example can be updated using:

.. code-block:: bash

    ./tools/registry/update_example.sh

That change can be undone via:

.. code-block:: bash

    ./tools/registry/revert_example.sh

The registry can be stopped with:

.. code-block:: bash

    ./tools/registry/stop.sh


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
then uses it to generate certificates and construct scripts:

.. code-block:: bash

    ./tools/dev-build.sh examples/basic build


Using Promenade Behind a Proxy
------------------------------

To use Promenade from behind a proxy, use the proxy settings see
:doc:`configuration/kubernetes-network`.
