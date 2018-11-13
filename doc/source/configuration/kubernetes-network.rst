Kubernetes Network
==================

Configuration for Kubernetes networking during bootstrapping and for the
``kubelet``.


Sample Document
---------------

.. code-block:: yaml

    schema: promenade/KubernetesNetwork/v1
    metadata:
      schema: metadata/Document/v1
      name: kubernetes-network
      layeringDefinition:
        abstract: false
        layer: site
    data:
      dns:
        cluster_domain: cluster.local
        service_ip: 10.96.0.10
        bootstrap_validation_checks:
          - calico-etcd.kube-system.svc.cluster.local
          - kubernetes-etcd.kube-system.svc.cluster.local
          - kubernetes.default.svc.cluster.local
        upstream_servers:
          - 8.8.8.8
          - 8.8.4.4

      kubernetes:
        apiserver_port: 6443
        haproxy_port: 6553
        pod_cidr: 10.97.0.0/16
        service_cidr: 10.96.0.0/16
        service_ip: 10.96.0.1

      etcd:
        container_port: 2379
        haproxy_port: 2378

      hosts_entries:
        - ip: 192.168.77.1
          names:
            - registry

      proxy:
        url: http://proxy.example.com:8080
        additional_no_proxy:
          - 192.168.77.1


DNS
---

The data in the ``dns`` key is used for bootstrapping and ``kubelet``
configuration of cluster and host-level DNS, which is provided by coredns_.

``bootstrap_validation_checks``
    Domain names to resolve during the genesis and join processes for validation.

``cluster_domain``
    The Kubernetes cluster domain.  Used by the ``kubelet``.

``service_ip``
    The IP to use for cluster DNS.  Used by the ``kubelet``.

``upstream_servers``
    Upstream DNS servers to be configured in `/etc/resolv.conf`.


Kubernetes
----------

The ``kubernetes`` key contains:

``apiserver_port``
    The port that the Kubernetes API server process will listen on hosts where it runs.

``haproxy_port``
    The port that HAProxy will listen on on each host.  This port will be used
    by the ``kubelet`` and ``kube-proxy`` to find API servers in the cluster.

``pod_cidr``
    The CIDR from which the Kubernetes Controller Manager assigns pod IPs.

``service_cidr``
    The CIDR from which the Kubernetes Controller Manager assigns service IPs.

``service_ip``
    The in-cluster Kubernetes service IP.


.. _coredns: https://github.com/coredns/coredns
