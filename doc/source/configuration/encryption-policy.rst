EncryptionPolicy
================

Encryption policy defines how encryption should be applied via Promenade, either
directly or via charts maintained in the Promenade project.

Encrypting script in-line data
------------------------------

The primary use-case for this is to encrypt ``genesis.sh`` or ``join.sh`` scripts.

.. code-block:: yaml

    ---
    schema: promenade/EncryptionPolicy/v1
    metadata:
      schema: metadata/Document/v1
      name: encryption-policy
      layeringDefinition:
        abstract: false
        layer: site
      storagePolicy: cleartext
    data:
      scripts:
        genesis:
          gpg: {}
    ...


Scripts
^^^^^^^

The genesis and join scripts can be built with sensitive content encrypted.
Currently the only encryption method available is ``gpg``, which can be enabled
by setting that key to an empty dictionary.

Kubernetes apiserver persistence encryption
-------------------------------------------

Kubernetes supports `encrypting data`_ it writes to etcd. This is defined by an
encryption policy document enabled using a CLI option for the apiserver binary.
Separating out the policy into the EncryptionPolicy document is needed as there
must be guaranteed consistency between the policy put in place for bootstrapping
the cluster and apiservers put in place via Helm chart.

Neither Promenade, nor the apiserver chart, do anything to ensure you do not lock
yourself out of your data. When rotating encryption keys, you will need to always
leave all keys that reflect data currently encrypted in the profile. Note the
instructions on how to rotate keys in the linked Kubernetes documentation.

To make this encryption configuration effective, you must substitute into two
other documents

  * Substitute ``.etcd`` into ``.apiserver.encryption`` of your Genesis profile
    document.

  * Substitute ``.etcd`` into ``.values.conf.encryption_provider.content.resources``
    of your Armada chart definition for the apiserver chart. See the Promenade
    ``basic`` examples for reference.

.. code-block:: yaml

    ---
    schema: promenade/EncryptionPolicy/v1
    metadata:
      schema: metadata/Document/v1
      name: encryption-policy
      layeringDefinition:
        abstract: false
        layer: site
      storagePolicy: cleartext
    data:
      etcd:
        - resources:
            - 'secrets'
          providers:
            - secretbox:
                keys:
                 - name: key1
                   secret: blzKzBp6wkjU/2xzBqzgJV9FrVkkjBTT43mbctIhdPQ=
    ...

.. _encrypting data: https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
