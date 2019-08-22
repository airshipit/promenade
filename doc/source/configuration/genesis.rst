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
      tiller:
        listen: 24134
        probe_listen: 24135
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
        helm:
          tiller: gcr.io/kubernetes-helm/tiller:v2.14.0
        kubernetes:
          apiserver: gcr.io/google_containers/hyperkube-amd64:v1.11.6
          controller-manager: gcr.io/google_containers/hyperkube-amd64:v1.11.6
          etcd: quay.io/coreos/etcd:v3.0.17
          scheduler: gcr.io/google_containers/hyperkube-amd64:v1.11.6
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
    helm:
      tiller: <Tiller image for bootstrapping>
    kubernetes:
      apiserver: <API server image for bootstrapping>
      controller-manager: <Controller Manager image for bootstrapping>
      etcd: <etcd image for bootstrapping>
      scheduler: <Scheduler image for bootstrapping>
