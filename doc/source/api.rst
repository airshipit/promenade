.. _api-ref:

Promenade API Documentation
===========================


/v1.0/health
------------

Allows other components to validate Promenade's health status.

GET /v1.0/health

Returns the health status.

Responses:

+ 204 No Content


/v1.0/join-scripts
------------------

Generates join scripts and for Drydock.

GET /v1.0/join-scripts

Generates script to be consumed by Drydock.

Query parameters

hostname
    Name of the node
ip
    IP address of the node
design_ref
    Endpoint containing configuration documents
dynamic.labels
    Used to set configuration options in the generated script
static.labels
    Used to set configuration options in the generated script

Responses:

+ 200 OK: Script returned as response body
+ 400 Bad Request: One or more query parameters is missing or misspelled


/v1.0/validatedesign
--------------------

Performs validations against specified documents.

POST /v1.0/validatedesign

Performs validation against specified documents.

Message Body

href
    Location of the document to be validated

Responses:

+ 200 OK: Documents were successfully validated
+ 400 Bad Request: Documents were not successfully validated


/v1.0/node-labels/<node_name>
-----------------------------

Update node labels

PUT /v1.0/node-labels/<node_name>

Updates node labels eg: adding new labels, overriding existing
labels and deleting labels from a node.

Message Body:

dict of labels

.. code-block:: json

   {"label-a": "value1", "label-b": "value2", "label-c": "value3"}

Responses:

+ 200 OK: Labels successfully updated
+ 400 Bad Request: Bad input format
+ 401 Unauthorized: Unauthenticated access
+ 403 Forbidden: Unauthorized access
+ 404 Not Found: Bad URL or Node not found
+ 500 Internal Server Error: Server error encountered
+ 502 Bad Gateway: Kubernetes Config Error
+ 503 Service Unavailable: Failed to interact with Kubernetes API
