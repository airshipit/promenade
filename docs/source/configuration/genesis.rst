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
        armada: quay.io/attcomdev/armada:latest
        helm:
          tiller: gcr.io/kubernetes-helm/tiller:v2.7.2
        kubernetes:
          apiserver: gcr.io/google_containers/hyperkube-amd64:v1.8.6
          controller-manager: gcr.io/google_containers/hyperkube-amd64:v1.8.6
          etcd: quay.io/coreos/etcd:v3.0.17
          scheduler: gcr.io/google_containers/hyperkube-amd64:v1.8.6
      files:
        - path: /var/lib/anchor/calico-etcd-bootstrap
          content: ""
          mode: 0644


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
