# Promenade Configuration

Promenade is configured using a set Kubernetes-like YAML documents.  Many of
these documents can be automatically derived from a few core configuration
documents or generated automatically (e.g. certificates).  All of these
documents can be specified in detail allowing for fine-grained control over
cluster deployment.

Generally, these documents have the following form:

```yaml
---
apiVersion: promenade/v1
kind: Kind
metadata:
  compliant: metadata
spec:
  detailed: data
```

`apiVersion` identifies the document as Promenade configuration.  Currently
only `promenade/v1` is supported.

`kind` describe the detailed type of document.  Valid kinds are:

- `Certificate` - An x509 certificate.
- `CertificateAuthority` - An x509 certificate authority certificate.
- `CertificateAuthorityKey` - The private key for a certificate authority.
- `CertificateKey` - The private key for a certificate.
- `Cluster` - Cluster configuration containing node host names, IPs & roles.
- `Etcd` - Specific configuration for an etcd cluster.
- `Masters` - Host names and IPs of master nodes.
- `Network` - Configuration details for Kubernetes networking components.
- `Node` - Specific configuration for a single host.
- `PrivateKey` - A private key, e.g. the `controller-manager`'s token signing key.
- `PublicKey` - A public key, e.g. the key for verifying service account tokens.
- `Versions` - Specifies versions of packages and images to be deployed.

`metadata` are used to select specific documents of a given `kind`.  For
example, the various services must each select their specific `Certificate`s.
`metadata` are also used by Drydock to select the configuration files that are
needed for a particular node.

`spec` contains specific data for each kind of configuration document.

## Generating Configuration from Minimal Input

To construct a complete set of cluster configuration, the minimal input are
`Cluster`, `Network` and `Versions` documents.  To see complete examples of
these, please see the [example](example/vagrant-input-config.yaml).

The `Cluster` configuration must contain an entry for each host for which
configuration should be generated.  Each host must contain an `ip`, and
optionally `roles` and `additional_labels`.  Valid `roles` are currently
`genesis` and `master`.  `additional_labels` are Kubernetes labels which will
be added to the node.

Here's an example `Cluster` document:

```yaml
apiVersion: promenade/v1
kind: Cluster
metadata:
  name: example
  target: none
spec:
  nodes:
    n0:
      ip: 192.168.77.10
      roles:
        - master
        - genesis
      additional_labels:
        - beta.kubernetes.io/arch=amd64
```

The `Network` document must contain:

- `cluster_domain` - The domain for the cluster, e.g. `cluster.local`.
- `cluster_dns` - The IP of the cluster DNS,e .g. `10.96.0.10`.
- `kube_service_ip` - The IP of the `kubernetes` service, e.g. `10.96.0.1`.
- `pod_ip_cidr` - The CIDR from which pod IPs will be assigned, e.g. `10.97.0.0/16`.
- `service_ip_cidr` - The CIDR from which service IPs will be assigned, e.g. `10.96.0.0/16`.
- `etcd_service_ip` - The IP address of the `etcd` service, e.g. `10.96.232.136`.
- `dns_servers` - A list of upstream DNS server IPs.

Optionally, proxy settings can be specified here as well.  These should all
generally be set together: `http_proxy`, `https_proxy`, `no_proxy`.

Here's an example `Network` document:

```yaml
apiVersion: promenade/v1
kind: Network
metadata:
  cluster: example
  name: example
  target: all
spec:
  cluster_domain: cluster.local
  cluster_dns: 10.96.0.10
  kube_service_ip: 10.96.0.1
  pod_ip_cidr: 10.97.0.0/16
  service_ip_cidr: 10.96.0.0/16
  etcd_service_ip: 10.96.232.136
  dns_servers:
    - 8.8.8.8
    - 8.8.4.4
  http_proxy: http://proxy.example.com:8080
  https_proxy: http://proxy.example.com:8080
  no_proxy: 192.168.77.10,127.0.0.1,kubernetes
```

The `Versions` document must define the Promenade image to be used and the
Docker package version.  Currently, only the versions specified for these two
items are respected.

Here's an example `Versions` document:

```yaml
apiVersion: promenade/v1
kind: Versions
metadata:
  cluster: example
  name: example
  target: all
spec:
  images:
    promenade: quay.io/attcomdev/promenade:latest
  packages:
    docker: docker.io=1.12.6-0ubuntu1~16.04.1
```

Given these documents (see the [example](example/vagrant-input-config.yaml)),
Promenade can derive the remaining configuration and generate certificates and
keys using the following command:

```bash
mkdir -p configs
docker run --rm -t \
    -v $(pwd):/target \
    quay.io/attcomdev/promenade:latest \
    promenade -v generate \
      -c /target/example/vagrant-input-config.yaml \
      -o /target/configs
```

This will generate the following files in the `configs` directory:

- `up.sh` - A script which will bring up a node to create or join a cluster.
- `admin-bundle.yaml` - A collection of generated certificates, private keys
  and core configuration.
- `complete-bundle.yaml` - A set of generated documents suitable for upload
  into Drydock for future delivery to nodes to be provisioned to join the
  cluster.

Additionally, a YAML file for each host described in the `Cluster` document
will be placed here.  These files each contain every document needed for that
particular node to create or join the cluster.
