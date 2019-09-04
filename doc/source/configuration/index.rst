Configuration
=============

Promenade is configured using a set of Deckhand_ compatible configuration
documents and a bootstrapping Armada_ manifest that is responsible for
deploying core components into the cluster.

Details about Promenade-specific documents can be found here:

.. toctree::
    :maxdepth: 2
    :caption: Documents

    docker
    encryption-policy
    genesis
    host-system
    kubelet
    kubernetes-network
    kubernetes-node
    pki-catalog


The provided Armada_ manifest and will be applied on the genesis node as soon
as it is healthy.


.. _Armada: https://opendev.org/airship/armada
.. _Deckhand: https://opendev.org/airship/deckhand
