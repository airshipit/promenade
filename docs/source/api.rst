Promenade API
=============


/v1.0/health
------------

Allows other components to validate Promenade's health status.

GET /v1.0/health

Returns the health status.

Responses
- 204 No Content


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

Responses
- 204 No Content: Scripts generated successfully
- 400 Bad Request: One or more query parameters is missing or misspelled


/v1.0/validatedesign
--------------------

Performs validations against specified documents.

POST /v1.0/validatedesign

Performs validation against specified documents.

Message Body
href
    Location of the document to be validated
type
    Type of document to be validated

Responses:
- 200 OK: Documents were successfully validated
- 400 Bad Request: Documents were not successfully validated
- 404 Not Found: The document (of that type) was not found at the specified location
