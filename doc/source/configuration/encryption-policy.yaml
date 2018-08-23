EncryptionPolicy
================

Encryption policy defines how encryption should be applied via Promenade.  The
primary use-case for this is to encrypt ``genesis.sh`` or ``join.sh`` scripts.

Sample Document
---------------

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
-------

The genesis and join scripts can be built with sensitive content encrypted.
Currently the only encryption method available is ``gpg``, which can be enabled
by setting that key to an empty dictionary.
