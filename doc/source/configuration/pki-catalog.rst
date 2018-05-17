PKI Catalog
===========

Configuration for certificate and keypair generation in the cluster.  The
``promenade generate-certs`` command will read all ``PKICatalog`` documents and
either find pre-existing certificates/keys, or generate new ones based on the
given definition.


Sample Document
---------------

Here is a sample document:

.. code-block:: yaml

    schema: promenade/PKICatalog/v1
    metadata:
      schema: metadata/Document/v1
      name: cluster-certificates
      layeringDefinition:
        abstract: false
        layer: site
    data:
      certificate_authorities:
        kubernetes:
          description: CA for Kubernetes components
          certificates:
            - document_name: apiserver
              description: Service certificate for Kubernetes apiserver
              common_name: apiserver
              hosts:
                - localhost
                - 127.0.0.1
                - 10.96.0.1
              kubernetes_service_names:
                - kubernetes.default.svc.cluster.local
            - document_name: kubelet-genesis
              common_name: system:node:n0
              hosts:
                - n0
                - 192.168.77.10
              groups:
                - system:nodes
            - document_name: kubelet-n0
              common_name: system:node:n0
              hosts:
                - n0
                - 192.168.77.10
              groups:
                - system:nodes
            - document_name: kubelet-n1
              common_name: system:node:n1
              hosts:
                - n1
                - 192.168.77.11
              groups:
                - system:nodes
            - document_name: kubelet-n2
              common_name: system:node:n2
              hosts:
                - n2
                - 192.168.77.12
              groups:
                - system:nodes
            - document_name: kubelet-n3
              common_name: system:node:n3
              hosts:
                - n3
                - 192.168.77.13
              groups:
                - system:nodes
            - document_name: scheduler
              description: Service certificate for Kubernetes scheduler
              common_name: system:kube-scheduler
            - document_name: controller-manager
              description: certificate for controller-manager
              common_name: system:kube-controller-manager
            - document_name: admin
              common_name: admin
              groups:
                - system:masters
            - document_name: armada
              common_name: armada
              groups:
                - system:masters
        kubernetes-etcd:
          description: Certificates for Kubernetes's etcd servers
          certificates:
            - document_name: apiserver-etcd
              description: etcd client certificate for use by Kubernetes apiserver
              common_name: apiserver
            - document_name: kubernetes-etcd-anchor
              description: anchor
              common_name: anchor
            - document_name: kubernetes-etcd-genesis
              common_name: kubernetes-etcd-genesis
              hosts:
                - n0
                - 192.168.77.10
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n0
              common_name: kubernetes-etcd-n0
              hosts:
                - n0
                - 192.168.77.10
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n1
              common_name: kubernetes-etcd-n1
              hosts:
                - n1
                - 192.168.77.11
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n2
              common_name: kubernetes-etcd-n2
              hosts:
                - n2
                - 192.168.77.12
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n3
              common_name: kubernetes-etcd-n3
              hosts:
                - n3
                - 192.168.77.13
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
        kubernetes-etcd-peer:
          certificates:
            - document_name: kubernetes-etcd-genesis-peer
              common_name: kubernetes-etcd-genesis-peer
              hosts:
                - n0
                - 192.168.77.10
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n0-peer
              common_name: kubernetes-etcd-n0-peer
              hosts:
                - n0
                - 192.168.77.10
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n1-peer
              common_name: kubernetes-etcd-n1-peer
              hosts:
                - n1
                - 192.168.77.11
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n2-peer
              common_name: kubernetes-etcd-n2-peer
              hosts:
                - n2
                - 192.168.77.12
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
            - document_name: kubernetes-etcd-n3-peer
              common_name: kubernetes-etcd-n3-peer
              hosts:
                - n3
                - 192.168.77.13
                - 127.0.0.1
                - localhost
                - kubernetes-etcd.kube-system.svc.cluster.local
        calico-etcd:
          description: Certificates for Calico etcd client traffic
          certificates:
            - document_name: calico-etcd-anchor
              description: anchor
              common_name: anchor
            - document_name: calico-etcd-n0
              common_name: calico-etcd-n0
              hosts:
                - n0
                - 192.168.77.10
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-etcd-n1
              common_name: calico-etcd-n1
              hosts:
                - n1
                - 192.168.77.11
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-etcd-n2
              common_name: calico-etcd-n2
              hosts:
                - n2
                - 192.168.77.12
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-etcd-n3
              common_name: calico-etcd-n3
              hosts:
                - n3
                - 192.168.77.13
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-node
              common_name: calcico-node
        calico-etcd-peer:
          description: Certificates for Calico etcd clients
          certificates:
            - document_name: calico-etcd-n0-peer
              common_name: calico-etcd-n0-peer
              hosts:
                - n0
                - 192.168.77.10
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-etcd-n1-peer
              common_name: calico-etcd-n1-peer
              hosts:
                - n1
                - 192.168.77.11
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-etcd-n2-peer
              common_name: calico-etcd-n2-peer
              hosts:
                - n2
                - 192.168.77.12
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-etcd-n3-peer
              common_name: calico-etcd-n3-peer
              hosts:
                - n3
                - 192.168.77.13
                - 127.0.0.1
                - localhost
                - 10.96.232.136
            - document_name: calico-node-peer
              common_name: calcico-node-peer
    keypairs:
      - name: service-account
        description: Service account signing key for use by Kubernetes controller-manager.


Certificate Authorities
-----------------------

The data in the ``certificate-authorities`` key is used to generate certificates for each
authority and node.

Each certificate authority requires essential host-specific information for each node, including
the ``hostname`` and ``ip`` as listed in each :doc:`kubernetes-node` document.
