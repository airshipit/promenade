Kubernetes Node
===============

Configuration for a basic node in the cluster.


Sample Document
---------------

Here is a sample document:

.. code-block:: yaml

    schema: promenade/KubernetesNode/v1
    metadata:
      schema: metadata/Document/v1
      name: n1
      layeringDefinition:
        abstract: false
        layer: site
    data:
      hostname: n1
      ip: 192.168.77.11
      join_ip: 192.168.77.10
      labels:
        static:
          - node-role.kubernetes.io/master=
        dynamic:
          - calico-etcd=enabled
          - kubernetes-apiserver=enabled
          - kubernetes-controller-manager=enabled
          - kubernetes-etcd=enabled
          - kubernetes-scheduler=enabled
          - ucp-control-plane=enabled


Host Information
----------------

Essential host-specific information is specified in this document, including
the ``hostname``, ``ip``, and ``join_ip``.

The ``join_ip`` is used to specify which host should be used when adding a node
to the cluster.


Labels
------

Kubernetes labels can be specified under the ``labels`` key in two ways:

1. Via the ``static`` key, which is a list of labels to be applied immediately
   when the ``kubelet`` process starts.
2. Via the ``dynamic`` key, which is a list of labels to be applied after the
   node is marked as `Ready` by Kubernetes.
