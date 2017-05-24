# Overview

Promenade is tool for deploying self-hosted, highly resilient Kubernetes clusters using
[bootkube](https://github.com/kubernetes-incubator/bootkube). Currently. Promenade works by leveraging Docker containers with the Bootkube binaries in order to setup Kubernetes on the host operating system. Default Kubernetes assets and manifests are included in this repo, but it is recommended to render or supply your own assets for real-world deployments.

## Quickstart using Vagrant

Make sure you have [Vagrant](https://vagrantup.com) and
[VirtualBox](https://www.virtualbox.org/wiki/Downloads) installed.  Then
install the `vagrant-hostmanager` plugin.

```bash
vagrant plugin install vagrant-hostmanager
```

Build the genesis and join images and save them to disk for quick loading into
the Vagrant VMs.

```bash
make save
```

Start the VMs and save a snapshot for quicker iteration:

```bash
vagrant up
vagrant snapshot save clean
```

Spin up a cluster:

```bash
./test-install.sh
```

Watch nodes spin up:

```bash
watch kubectl --insecure-skip-tls-verify --kubeconfig <(sed 's/kubernetes:443/192.168.77.10:443/' < assets/kubeconfig) get nodes
```

To test changes, you can safely reset single or multiple nodes:

```bash
vagrant snapshot resotre n2 clean --no-provision
vagrant snapshot restore clean --no-provision
```

## Detailed Deployment

The below steps can be used to deploy a cluster on bare metal or virtual nodes:

1. Overwrite the placeholder assets in the `assets` directory.

2. Make sure the `Makefile` lists the images and versions you expect to be
   required.

3. Build the images with `make build`

4. Setup each host with the following:
   - DNS resolution pointing `kubernetes` to the appropriate IPs (Kubernetes master nodes) for the
     Kubernetes API
   - A running docker daemon, configured to use the DNS resolution specified
     above (see `vagrant-assets/docker-daemon.json`)     

5. Transfer the appropriate images to each host.  You may find it useful to
   run `make save`, transfer the image and then use `docker load -i ...` to
   restore it rather than to rely on a registry.

6. On the genesis (seed) server, start the cluster supplying in the node's FQDNs:
   `docker run --rm -v /:/target -v /var/run/docker.sock:/var/run/docker.sock -e NODE_HOSTNAME=genesis-node.fqdn quay.io/attcomdev/promenade-genesis:dev`

7. On each additional node to be joined to the cluster:
   `docker run --rm -v /:/target -v /var/run/docker.sock:/var/run/docker.sock -e NODE_HOSTNAME=join-node.fqdn quay.io/attcomdev/promenade-join:dev`


## References:

1. [Demo of Genesis Node Deployment](https://asciinema.org/a/c2fdtzh2z2fiymiyu75b32u0h)

2. [Demo of Joining Node to Cluster](https://asciinema.org/a/62dssvuiwbdanfuwwe6vzcihk)
