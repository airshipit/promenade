# Promenade

Promenade is a tool for bootstrapping a resilient Kubernetes cluster and
managing its life-cycle via Helm charts.

Documentation can be found [here](https://airship-promenade.readthedocs.io).

## Roadmap

The detailed Roadmap can be viewed on the
[OpenStack StoryBoard](https://storyboard.openstack.org/#!/project/1009).

- Cluster bootstrapping
  - Initial Genesis process results in a single node Kubernetes cluster with
    Under-cloud components deployed using
    [Armada](https://git.airshipit.org/cgit/airship-armada/).
  - Joining sufficient master nodes results in a resilient Kubernetes cluster.
  - Destroy Genesis node after bootstrapping and re-provision as a normal node
    to ensure consistency.
- Life-cycle management
  - Decommissioning of nodes.
  - Updating Kubernetes version.

## Getting Started

To get started, see
[getting started](https://airship-promenade.readthedocs.io/en/latest/getting-started.html).

Configuration is documented
[here](https://airship-promenade.readthedocs.io/en/latest/configuration/index.html).

## Bugs

Bugs are tracked in
[OpenStack StoryBoard](https://storyboard.openstack.org/#!/project/1009).
