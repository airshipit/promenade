Developer On-boarding
=====================

Overview
--------

Functionality:

- Airship Bootstrapping
- Core Kubernetes Management
- Misc.

Code structure:

1. Jinja templates (``promenade/templates/**``).
2. Helm charts for Kubernetes components, etcd, CoreDNS, Promenade ``charts/**``.
3. Python support code.

    * API
    * Config access object
    * CLI
    * Certificate generation code

Since Promenade is largely templates + charts, unit testing is not enough to
provide confidence for code changes.  Significant functional testing is
required to test small changes to, e.g. the ``etcd`` or ``calico`` charts,
which can completely break deployment (or break reboot recovery).  Developers
can run the functional tests locally:

.. code-block:: console

    ./tools/setup_gate.sh  # Run once per machine you're on, DO NOT USE SUDO.
    ./tools/gate.sh        # Runs a 4 node resiliency test.

This runs the test defined in ``tools/g2/manifests/resiliency.json``.  There
are a few additional test scenarios defined in adjacent files.

There are helpful tools for troubleshooting these gates in ``tools/g2/bin/*``,
including ``tools/g2/bin/ssh.sh``, which will let you ssh directly to a node to
debug it, e.g.:

.. code-block:: console

    ./tools/g2/bin/ssh.sh n0

Bootstrapping
-------------

Promenade is responsible for converting a vanilla Ubuntu 16.04 VM into a proper
Airship.

How You Run It
^^^^^^^^^^^^^^

Assuming you have a `valid set of configuration`_.  Generate `genesis.sh`,
which is a self-contained script for bootstrapping the genesis node.

.. code-block:: console

    promenade build-all -o output-dir config/*.yaml

What ``genesis.sh`` does:

1. Basic host validation (always room for more).
2. Drops pre-templated files in place:

    * Manifests to run initial Kubernetes components
      ``/etc/kubernetes/manifests``

        * Basic components (apiserver, scheduler, controller-manager)
        * Etcd
        * Auxiliary Etcd

    * Docker configuration
    * Kubelet configuration
    * Apt configuration (proxy)
    * Bootstrapping Armada configuration

        * Dedicated Tiller
        * Dedicated Kubernetes API server
        * API server points at auxiliary etcd.

3. Installs some apt packages (docker + user-defined)
4. Starts Docker and Kubernetes.
5. Waits for bootstrapping services to be up (healthy Kubernetes API).
6. Applies configured labels to node.
7. Waits for Armada to finish bootstrapping deployment.
8. Final host validation.

When it's done, you should have a working Airship deployed as defined by your
configuration (e.g. with or without LMA, keystone, etc) with no configuration
loaded into Deckhand (via Shipyard).

How It Works
^^^^^^^^^^^^

The templates that get dropped in place generally live in
``promenade/templates/**``.  The genesis node gets everything under
``roles/genesis/**`` and ``roles/common/**`` directly in place.  Note that the
templates under ``roles/join/**`` are used instead of the files under
``genesis`` for joining nodes to the existing cluster.

The "real" work happens inside ``kubelet`` managed "static" pods (defined by
flat files in ``/etc/kubernetes/manifests``), primarily via Armada.

Charts do a bunch of work to take control of essentially everything behind the
scenes.  Trickiest is ``etcd``, for which we run multiple server processes to
keep the cluster happy throughout bootstrapping + initial node join.

Note that we deploy two separate etcd clusters:  one for Kubernetes itself, and
one for Calico.  The Calico one is a bit less sensitive.

Anchor Pattern
~~~~~~~~~~~~~~

To provide increased resiliency, we do something a bit unusual with the core
components.  We run a ``DaemonSet`` for them which simply copy static ``Pod``
definitions into the ``/etc/kubernetes/manifests`` directory on the hosts
(along with any supporting files/configuration).  This ensures that these
workloads are present even when the Kubernetes API server is unreachable.  We
call this pattern the ``Anchor`` pattern.

The following components follow this pattern:

* Kubernetes core components

  * API server
  * Scheduler
  * Controller Manager

* Kubernetes etcd
* Calico etcd
* HAProxy (used for API server discovery)

The HAProxy ``DaemonSet`` runs on every machine in the cluster, but the others
only run on "master" nodes.

Kubernetes Cluster Management
-----------------------------

Promenade is responsible for managing the Kubernetes lifecycle of nodes.  That
primarily consists of "joining" them to the cluster and adding labels, but also
includes label updates and node removal.

Node Join
^^^^^^^^^

This is done via a self-contained script that is obtained by Drydock querying
the Promenade API ``GET /api/v1.0/join-scripts`` (and providing a configuration
link to Deckhand originally specified by Shipyard).

The join script is delivered to the node by Drydock and executed via a systemd
unit.  When it runs, it follows a similar pattern to ``genesis.sh``, but
naturally does not use any Kubernetes bootstrapping components or run Armada:

1. Basic host validation (always room for more).
2. Drops pre-templated files in place:

    * Docker configuration
    * Kubelet configuration
    * Apt configuration (proxy)

3. Installs some apt packages (docker + user-defined)
4. Starts Docker and Kubernetes.
5. Waits for node to be recognized by Kubernetes.
6. Applies configured labels to node.
7. Final host validation.

After the node has successfully joined, the systemd unit disables itself so
that it is not run again on reboot (though it would be safe to do so).

Other Management Features
^^^^^^^^^^^^^^^^^^^^^^^^^

Re-labeling and node removal API development has been delayed for other
priorities, but is recently underway.  While changing labels is generally easy,
there are a few trickier bits around Kubelet and etcd management.

It is currently possible to fully de-label and remove a node from the cluster
using a script that gets placed on each node (it requires ``kubectl`` so that
must be in place), but that work is not exposed via API yet.  The resiliency
gate exercises this to reprovision the genesis node as a normal node.

Miscellaneous
-------------

Promenade does a few bits of additional work that's hard to classify, and
probably don't belong in scope long term.  Most notably is certificate
generation.

Certificate generation is configured by the ``PKICatalog`` configuration
document, which specifies the details for each certificate (CN, groups, hosts).
Promenade then translates those requirements into calls to ``cfssl``.  The
following will create a ``certificates.yaml`` file in ``output-dir`` containing
all the generated certs:

.. code-block:: console

    promenade generate-certs -o output-dir config/*.yaml

If there are existing certs in ``config/*.yaml``, then they will be used if
applicable.

Troubleshooting
---------------

The context for this section is the functional gates described above.  You can
run them with:

.. code-block:: console

    ./tools/gate.sh <gate_name>

When something goes wrong with this, you can ssh into individual nodes for
testing (the nodes are named ``n0`` through ``n3``):

.. code-block:: console

    ./tools/g2/bin/ssh.sh <node_name>

When you get into a node and see various failures, or have an Armada error
message saying a particular chart deployment failed, it is important to assess
the overall cluster rather than just digging into the first thing you see.  For
example, if there is a problem with ``etcd``, it could manifest as the Kubernetes
API server pods failing.

Here is an approximate priority list of what to check for health (i.e. things
higher up in the list break things lower down):

1. Kubernetes etcd
2. Kubernetes API Server
3. Other Kubernetes components (scheduler, controller-manager, kubelet).
4. Kubernetes proxy
5. Calico etcd
6. Calico node
7. DNS (CoreDNS)

For almost any other application, all of the above must be healthy before they
will function properly.


.. _`valid set of configuration`: https://github.com/openstack/airship-in-a-bottle
