Kubelet
=======

Configuration for the Kubernetes worker daemon (the Kubelet).  This document
contains three keys: ``arguments``, ``images``, and ``config_file_overrides``.
The ``arguments`` are appended directly to the ``kubelet`` command line,
along with arguments that are controlled by Promenade more directly.
The ``config_file_overrides`` are appended directly to the static kubelet
configuration file and only consists of a subset of kubelet arguments.
More information regarding the format for this key can be found here_.

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
        - --network-plugin=cni
        - --v=5
      images:
        pause: registry.k8s.io/pause-amd64:3.1
      config_file_overrides:
        evictionMaxPodGracePeriod: -1
        nodeStatusUpdateFrequency: "5s"

.. _here: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file
