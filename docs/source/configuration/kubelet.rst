Kubelet
=======

Configuration for the Kubernetes worker daemon (the Kubelet).  This document
contains two keys: ``arguments`` and ``images``.  The ``arguments`` are
appended directly to the ``kubelet`` command line, along with arguments that
are controlled by Promenade more directly.

The only image that is configurable is for the ``pause`` container.


Sample Document
---------------

Here is a sample document:

.. code-block:: yaml

    schema: promenade/Kubelet/v1
    metadata:
      schema: metadata/Document/v1
      name: kubelet
      layeringDefinition:
        abstract: false
        layer: site
    data:
      arguments:
        - --cni-bin-dir=/opt/cni/bin
        - --cni-conf-dir=/etc/cni/net.d
        - --eviction-max-pod-grace-period=-1
        - --network-plugin=cni
        - --node-status-update-frequency=5s
        - --v=5
      images:
        pause: gcr.io/google_containers/pause-amd64:3.0
