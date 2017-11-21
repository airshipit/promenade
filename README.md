# Promenade

Promenade is a tool for bootstrapping a resilient Kubernetes cluster and
managing its life-cycle via Helm charts.

Documentation can be found [here](https://promenade.readthedocs.io).

## Roadmap

The detailed Roadmap can be viewed on the
[LCOO JIRA](https://openstack-lcoo.atlassian.net/secure/RapidBoard.jspa?projectKey=PROM&rapidView=37).

- Cluster bootstrapping
  - Initial Genesis process results in a single node Kubernetes cluster with
    Under-cloud components deployed using
    [Armada](https://github.com/att-comdev/armada).
  - Joining sufficient master nodes results in a resilient Kubernetes cluster.
  - Destroy Genesis node after bootstrapping and re-provision as a normal node
    to ensure consistency.
- Life-cycle management
  - Decommissioning of nodes.
  - Updating Kubernetes version.

## Getting Started

To get started, see
[getting started](https://promenade.readthedocs.io/en/latest/getting-started.html).

Configuration is documented
[here](https://promenade.readthedocs.io/en/latest/configuration/index.html).

## Bugs

Bugs are tracked in
[LCOO JIRA](https://openstack-lcoo.atlassian.net/secure/RapidBoard.jspa?projectKey=PROM&rapidView=37).
If you find a bug, feel free to create a GitHub issue and it will be synced to
JIRA.
