Genesis Troubleshooting
=======================

genesis.sh
----------

Kubernetes services failures
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Before the Armada manifests are applied, the genesis.sh script will bring basic
kubernetes services online by starting docker containers for these services.

One of the first services to be brought up is the kubernetes API. If it fails to
come up, you may see a repeated error as follows from the genesis.sh script:

.. code-block:: console

    .The connection to the server apiserver.kubernetes.promenade:6443 was
    refused - did you specify the right host or port?

Check that the hostname in your Genesis.yaml matches the hostname of the
machine you are trying to install onto. If they do not match, change one to
match the other. If you change Genesis.yaml, then re-generate the Promenade
payloads.

If the hostnames match, check the container logs under /var/log/pods to see the
reason for the provisioning failure. (``kubectl logs`` function will not be
available if the API container is not running).

Armada failures
^^^^^^^^^^^^^^^

When executing genesis.sh, you may encounter failures from Armada in the
provisioning of other containers. For example:

.. code-block:: console

    CRITICAL armada [-] Unhandled error: armada.exceptions.tiller_exceptions.ReleaseException: Failed to Install release: barbican

Use ``kubectl logs`` on the failed pod to determine the reason for the failure.
E.g.:

.. code-block:: console

    sudo kubectl logs barbican-api-5b8bccdf8f-x7sld --namespace=ucp

Other errors may point to configuration errors. For example:

.. code-block:: console

    CRITICAL armada [-] Unhandled error: armada.exceptions.source_exceptions.GitLocationException: master is not a valid git repository.

In this case, the git branch name was inadvertently substituted for the git URL
in one of the chart definitions in ``bootstrap-armada.yaml``.

Post-run failures
^^^^^^^^^^^^^^^^^

At its conclusion, the genesis script will output the list of containers
provisioned and their status, as reported by kubernetes. It is possible that
some containers may not be in a Running state. E.g.:

.. code-block:: console

    ucp   promenade-api-6696769cd-qwpzf   0/1   ImagePullBackOff   0   10h

For general failures, ``kubectl logs`` may be used as in the previous section.
In this case, it was necessary to run ``kubectl describe`` on the pod to get the
details of the image pull failure. E.g.:

.. code-block:: console

    kubectl describe pod promenade-api-7dc54d47c-qw27m --namespace=ucp

In this particular incident report, the problem was a missing certificate on the
bare metal node which caused the image download to fail. Installing the
certificate, restarting the docker service, and then waiting for the container
to retry resolved this particular issue.
