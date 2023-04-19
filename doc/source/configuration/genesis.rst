Genesis
=======

Specific configuration for the genesis process.  This document is a strict
superset of the combination of :doc:`kubernetes-node` and :doc:`host-system`,
so only differences are discussed here.


Sample Document
---------------

Here is a complete sample document:

.. code-block:: yaml

    schema: promenade/Genesis/v1
    metadata:
      schema: metadata/Document/v1
      name: genesis
      layeringDefinition:
        abstract: false
        layer: site
    data:
      hostname: n0
      ip: 192.168.77.10
      armada:
        target_manifest: cluster-bootstrap
        metrics:
          output_dir: /var/log/armada/metrics
          max_attempts: 5
      labels:
        static:
          - calico-etcd=enabled
          - node-role.kubernetes.io/master=
        dynamic:
          - kubernetes-apiserver=enabled
          - kubernetes-controller-manager=enabled
          - kubernetes-etcd=enabled
          - kubernetes-scheduler=enabled
          - promenade-genesis=enabled
          - ucp-control-plane=enabled
      images:
        armada: quay.io/airshipit/armada:latest
        kubernetes:
          apiserver: registry.k8s.io/kube-apiserver-amd64:v1.26.0
          controller-manager: registry.k8s.io/kube-controller-manager-amd64:v1.26.0
          etcd: quay.io/coreos/etcd:v3.5.4
          scheduler: registry.k8s.io/kube-scheduler-amd64:v1.26.0
      files:
        - path: /var/lib/anchor/calico-etcd-bootstrap
          content: ""
          mode: 0644


Armada
------

Configuration options for bootstrapping with Armada.

+-----------------+----------+---------------------------------------------------------------------------------------+
| keyword         | type     | action                                                                                |
+=================+==========+=======================================================================================+
| target_manifest | string   | Specifies the ``armada/Manifest/v1`` to use during Genesis.                           |
+-----------------+----------+---------------------------------------------------------------------------------------+
| metrics         | object   | See `Metrics`_.                                                                       |
+-----------------+----------+---------------------------------------------------------------------------------------+

Metrics
^^^^^^^

Configuration for Armada bootstrap metric collection.

+-----------------+----------+---------------------------------------------------------------------------------------+
| keyword         | type     | action                                                                                |
+=================+==========+=======================================================================================+
| output_dir      | string   | (optional, default `/var/log/node-exporter-textfiles`) The directory path in which to |
|                 |          | output Armada metric data.                                                            |
+-----------------+----------+---------------------------------------------------------------------------------------+
| max_attempts    | integer  | (optional, default 10) The maximum Armada attempts to collect metrics for.            |
|                 |          | Can be set to 0 to disable metrics collection.                                        |
+-----------------+----------+---------------------------------------------------------------------------------------+

Bootstrapping Images
--------------------

Bootstrapping images are specified in the top level key ``images``:

.. code-block:: yaml

    armada: <Armada image for bootstrapping>
    kubernetes:
      apiserver: <API server image for bootstrapping>
      controller-manager: <Controller Manager image for bootstrapping>
      etcd: <etcd image for bootstrapping>
      scheduler: <Scheduler image for bootstrapping>
