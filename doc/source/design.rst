Design
======

Promenade is a Kubernetes_ cluster deployment tool with the following goals:

* Resiliency in the face of node loss and full cluster reboot.
* Bare metal node support without external runtime dependencies.
* Providing a fully functional single-node cluster to allow cluster-hosted
  `tooling <https://github.com/openstack/airship-treasuremap>`_ to provision the
  remaining cluster nodes.
* Helm_ chart managed component life-cycle.
* API-managed cluster life-cycle.


Cluster Bootstrapping
---------------------

The cluster is bootstrapped on a single node, called the genesis node.  This
node goes through a short-lived bootstrapping phase driven by static pod
manifests consumed by ``kubelet``, then quickly moves to chart-managed
infrastructure, driven by Armada_.

During the bootstrapping phase, the following temporary components are run as
static pods which are configured directly from Promenade's configuration
documents:

* Kubernetes_ core components

    * ``apiserver``
    * ``controller-manager``
    * ``scheduler``

* Etcd_ for use by the Kubernetes_ ``apiserver``
* Helm_'s server process ``tiller``
* CoreDNS_ to be used for Kubernetes_ ``apiserver`` discovery

With these components up, it is possible to leverage Armada_ to deploy Helm_
charts to manage these components (and additional components) going forward.

Though completely configurable, a typical Armada_ manifest should specify
charts for:

* Kubernetes_ components

    * ``apiserver``
    * ``controller-manager``
    * ``proxy``
    * ``scheduler``

* Cluster DNS (e.g. CoreDNS_)
* Etcd_ for use by the Kubernetes_ ``apiserver``
* A CNI_ provider for Kubernetes_ (e.g. Calico_)
* An initial under-cloud system to allow cluster expansion, including
  components like Armada_, Deckhand_, Drydock_ and Shipyard_.

Once these charts are deployed, the cluster is validated (currently, validation
is limited to resolving DNS queries and verifying basic Kubernetes
functionality including ``Pod`` scheduling log collection), and then the
genesis process is complete.  Additional nodes can be added to the cluster
using day 2 procedures.

After additional master nodes are added to the cluster, it is possible to
remove the genesis node from the cluster so that it can be fully re-provisioned
using the same process as for all the other nodes.


Life-cycle Management
---------------------

There are two sets of resources that require life-cycle management:  cluster
nodes and Kubernetes_ control plane components.  These two sets of resources
are managed differently.


Node Life-Cycle Management
^^^^^^^^^^^^^^^^^^^^^^^^^^

Node life-cycle management tools are provided via an API to be consumed by
other tools like Drydock_ and Shipyard_.

The life-cycle operations for nodes are:

1. Adding a node to the cluster
2. Removing a node from the cluster
3. Adding and removing node labels.


Adding a node to the cluster
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Adding a node to the cluster is done by running a shell script on the node that
installs the ``kubelet`` and configures it to find and join the cluster.  This
script can either be generated up front via the CLI, or it can be obtained via
the `join-scripts` endpoint of the API (development of this API is in-progress).

Nodes can only be joined assuming all the proper configuration documents are
available, including required certificates for Kubelet.


Removing a node from the cluster
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is currently possible by leveraging the ``promenade-teardown`` script
placed on each host.  API support for this function is planned, but not yet
implemented.

Adding and removing node labels
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is currently only possible directly via ``kubectl``, though API support
for this functionality is planned.

It through relabeling nodes that key day 2 operations functionality like moving
a master node are achieved.


Control-Plane Component Life-Cycle Management
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

With the exception of the Docker_ daemon and the ``kubelet``, life-cycle
management of control plane components is handled via Helm_ chart updates,
which are orchestrated by Armada_.

The Docker_ daemon is managed as an APT package, with configuration installed
at the time the node is configured to join the cluster.

The ``kubelet`` is directly installed and configured at the time nodes join the
cluster.  Work is in progress to improve the upgradability of ``kubelet`` via
either a system package or a chart.


Resiliency
----------

The two primary failure scenarios Promenade is designed to be resilient against
are node loss and full cluster restart.

Kubernetes_ has a well-defined `High Availability
<https://kubernetes.io/docs/admin/high-availability/>`_ pattern, which deals
well with node loss.

However, this pattern requires an external load balancer for ``apiserver``
discovery.  Since it is a goal of this project for the cluster to be able to
operate without ongoing external dependencies, we must avoid that requirement.

Additionally, in the event of full cluster restart, we cannot rely on any
response from the ``apiserver`` to give any ``kubelet`` direction on what
processes to run.  That means, each master node must be self-sufficient, so
that once a quorum of Etcd_ members is achieved the cluster may resume normal
operation.

The solution approach is two-pronged:

1. Deploy a local discovery mechanism for the ``apiserver`` processes on each
   node so that core components can always find the ``apiservers`` when their
   nodes reboot.
2. Apply the Anchor pattern described below to ensure that essential components
   on master nodes restart even when the ``apiservers`` are not available.

Currently, the discovery mechanism for the ``apiserver`` processes is provided
by CoreDNS_ via a zone file written to disk on each node.  This approach has
some drawbacks, which might be addressed in future work by leveraging a
HAProxy_ for discovery instead.


Anchor Pattern
^^^^^^^^^^^^^^

The anchor pattern provides a way to manage process life-cycle using Helm_
charts in a way that allows them to be restarted immediately in the event of a
node restart -- even when the Kubernetes_ ``apiserver`` is unreachable.

In this pattern, a ``DaemonSet`` called the ``anchor`` that runs on selected
nodes and is responsible for managing the life-cycle of assets deployed onto
the node file system.  In particular, these assets include a Kubernetes_
``Pod`` manifest to be consumed by ``kubelet`` and it manages the processes
specified by the ``Pod``.  That management continues even when the node
reboots, since static pods like this are run by the ``kubelet`` even when the
``apiserver`` is not available.

Cleanup of these resources is managed by the ``anchor`` pods' ``preStop``
life-cycle hooks.  This is usually simply removing the files originally placed
on the nodes' file systems, but, e.g. in the case of Etcd_, can actually be
used to manage more complex cleanup like removal from cluster membership.


Pod Checkpointer
~~~~~~~~~~~~~~~~

Before moving to the Anchor pattern above, the pod-checkpointer approach
pioneered by the Bootkube_ project was implemented.  While this is an appealing
approach, it unfortunately suffers from race conditions during full cluster
reboot.

During cluster reboot, the checkpointer copies essential static manifests into
place for the ``kubelet`` to run, which allows those components to start and
become available.  Once the ``apiserver`` and ``etcd`` cluster are functional,
``kubelet`` is able to register the failure of its workloads, and delete those
pods via the API.  This is where the race begins.

Once those pods are deleted from the ``apiserver``, the pod checkpointer
notices that the flagged pods are no longer scheduled to run on its node and
then deletes the static manifests for those pods.  Concurrently, the
``controller-manager`` and ``scheduler`` notice that new pods need to be
created and scheduled (sequentially) and begin that work.

If the new pods are created, scheduled and started on the node before pod
checkpointers on other nodes delete their critical services, then the cluster
may remain healthy after the reboot.  If enough nodes running the critical
services fail to start the newly created pods before too many are removed, then
the cluster does not recover from hard reboot.

The severity of this race is exacerbated by:

1. The sequence of events required to successfully replace these pods is long
   (``controller-manager`` must create pods, then ``scheduler`` can schedule
   pods, then ``kubelet`` can start pods).
2. The ``controller-manager`` and ``scheduler`` may need to perform leader
   election during the race, because the leader might have been killed early.
3. The failure to recover any one of the core sets of processes can cause the
   entire cluster to fail.  This is somewhat trajectory-dependent, e.g. if at
   least one ``controller-manager`` is scheduled before the
   ``controller-manager`` processes are all killed, then assuming the other
   processes are correctly restarted, then the ``controller-manager`` will also
   recover.
4. ``etcd`` is somewhat more sensitive to this race, because it requires two
   successfully restarted pods (assuming a 3 node cluster) rather than just one
   as the other components.

This race condition was the motivation for the construction and use of the
Anchor pattern.  In future versions of Kubernetes_, it may be possible to use
`built-in checkpointing <https://docs.google.com/document/d/1hhrCa_nv0Sg4O_zJYOnelE8a5ClieyewEsQM6c7-5-o/view#>`_ from the ``kubelet``.


Alternatives
------------

* Kubeadm_

    * Does not yet support
      `HA <https://github.com/kubernetes/kubeadm/issues/261>`_
    * Current approach to HA Etcd_ is to use the
      `etcd opreator <https://github.com/coreos/etcd-operator>`_, which
      recovers from cluster reboot by loading from an external backup snapshot
    * Does not support chart-based management of components

* kops_

    * Does not support `bare metal <https://github.com/kubernetes/features/issues/360>`_

* Bootkube_

    * Does not support automatic recovery from a
      `full cluster reboot <https://github.com/kubernetes-incubator/bootkube/blob/master/Documentation/disaster-recovery.md>`_
    * Does not yet support
      `full HA <https://github.com/kubernetes-incubator/bootkube/issues/311>`_
    * Adheres to different design goals (minimal direct server contact), which
      makes some of these changes challenging, e.g.
      `building a self-contained, multi-master cluster <https://github.com/kubernetes-incubator/bootkube/pull/684#issuecomment-323886149>`_
    * Does not support chart-based management of components


.. _Armada: https://github.com/openstack/airship-armada
.. _Bootkube: https://github.com/kubernetes-incubator/bootkube
.. _CNI: https://github.com/containernetworking/cni
.. _Calico: https://github.com/projectcalico/calico
.. _CoreDNS: https://github.com/coredns/coredns
.. _Deckhand: https://github.com/openstack/airship-deckhand
.. _Docker: https://www.docker.com
.. _Drydock: https://github.com/openstack/airship-drydock
.. _Etcd: https://github.com/coreos/etcd
.. _HAProxy: http://www.haproxy.org
.. _Helm: https://github.com/kubernetes/helm
.. _kops: https://github.com/kubernetes/kops
.. _Kubeadm: https://github.com/kubernetes/kubeadm
.. _Kubernetes: https://github.com/kubernetes/kubernetes
.. _Shipyard: https://github.com/openstack/airship-shipyard
