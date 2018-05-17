Docker
======

Configuration for the docker daemon.  This document contains a single `config`
key that directly translates into the contents of the `daemon.json` file
described in `Docker's configuration`_.


Sample Document
---------------

Here is a sample document:

.. code-block:: yaml

    schema: promenade/Docker/v1
    metadata:
      schema: metadata/Document/v1
      name: docker
      layeringDefinition:
        abstract: false
        layer: site
    data:
      config:
        live-restore: true
        storage-driver: overlay2


.. _Docker's configuration: https://docs.docker.com/engine/reference/commandline/dockerd/
