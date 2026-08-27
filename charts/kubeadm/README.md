# Kubeadm Day0 Chart

> *Take the Helm at Day 0*

This is not just a standard Helm chart — it is a **Day 0 chart**, designed to operate before Kubernetes even exists. It is a declarative tool that wraps, extends, and overrides [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) phases for cluster bootstrapping and upgrading.

## Key Capabilities

* **Day 0 / Day 1 (Bootstrap):** Declaratively generates custom bash scripts for `cloud-init` directly from `values.yaml` to execute `kubeadm init` and `kubeadm join` phases. The resulting scripts can run directly on the node or be passed as standard user-data payloads to cloud and bare-metal provisioners.
* **Day 2 (Reconfiguration & Upgrades):** Performs cluster reconfiguration and binary/component upgrades. When redeployed with updated `values.yaml`, it executes reconciliation logic to align the live cluster state with the target configuration.

## Architecture & Philosophy

Thanks to the `templates/lib/bundle` module, all chart outputs can be fully redefined or overridden directly via `values.yaml`. This provides the flexibility to adapt to many different infrastructure scenarios without modifying the chart's code, while maintaining strict alignment between Day 1 (bootstrap) and Day 2 (reconfiguration/upgrades) to prevent configuration drift.

Since the primary goal is to bootstrap Kubernetes precisely from zero (bare OS with no prior configuration) up to a fully functional Kubernetes API, and to maintain this configuration over time, the chart is intentionally kept as minimalistic as possible: its sole purpose is to solve the chicken-and-egg bootstrapping problem cleanly.

## Extracting Bootstrap Scripts

Because the chart generates standalone bootstrap scripts, you can use it for both manual and automated declarative cluster provisioning. The generated scripts accept command-line arguments to override configuration parameters derived from `values.yaml`.

### Option 1: Using `yq`
Requires `helm` and `yq`:

```bash
helm template kubeadm -f values.yaml --set manifests.secret_bootstrap=true \
  | yq eval '. | select(.kind == "Secret" and .metadata.name == "kubeadm-service-bootstrap") | .data["script"] | @base64d'
```

Tip: Pipe the extracted output directly into bash -s -- <args> to execute the script immediately with runtime arguments.

### Option 2: Using standard system utilities (`sed` + `base64`)

If `yq` is not available, you can rely on standard utilities present in most Linux distributions. Use `--set bootstrap.nodename=<nodename>` to select a specific node's configuration:

```
helm template kubeadm -f values.yaml --set manifests.secret_bootstrap=true --set bootstrap.nodename=node0 \
  | sed -n 's/^ *script: *\(.*\)/\1/p' | base64 -d
```

More examples are here [5].

Thanks to the `templates/lib/bundle` module, all charts outputs can be fully re-defined/overriden via modification of values.yaml. That gives ability to adjust it without chart code modfication to many different scenarios, but at the same time keep alignment between day 1(cluster bootstrapping) and day 2(re-configuration/upgrade) and prevent the configuration drift.

Since the goal is to bootstrap k8s precisely from the point where there is nothing configured on the nodes till the time k8s API is accessible and to be able to maintain/upgrade this configuration later, it's important to keep this chart as minimalistic as possible: it just has to be able to resolve chicken-and-egg bootstrapping problem.

## Roadmap

It's in development yet. Here are the remaining potential items (can be changed):
* kubeadm phase: make sure its config aligns with other phases. validate certain cli args and warn user if the config contradicts to the config of other phases
* Make dynamic linking mechanism of modules
* Based on dynamic linking make imperative commandline support
* Allow generation of not only init/join/anchor, but generalize this.
* Anchor daemonsets can be more flexible, e.g. upgrade can go as initContainer or even a separate job, anchor is needed to run as an addition container vip_haproxy or some other 'supporting' actions periodically.
* Vip_haproxy is not the only implementation. Potenitally we can support e.g. [kube_vip](https://kube-vip.io/docs/installation/static/), or ipvs/iptables as a backend for VIP (see [1] and [2] below). Those 4 are the most popular, but the implementation is really similar and can be done in anchorContainer
* Think if we want to also support alternative day2 (kube-proxy/core-dns).. probably not. kubadm is flexible enough.
* Try to support operations like cert rotation (with the same CA. Create a cronjob to rotate CA. If it is with invalid date it can be used for manual cert roation (create job from cronjob).
* There are also 2 scenarios when k8s switches from 1 to another CA: seamless (intermittent 2 CA) and abrupt, when we change everything and syncroniously restart all kubelets (e.g. using a special OS service))
* Try to get rid of kubeadm image. use some image with ncenter as a placeholder and chroot directly to the host. mount everything there (mount is unidirectial by default, so it's safe). use standerd k8s artifacts (gz with bins or rely on distro packages as alternative). if it's not the case we can support also extraction of the bins from the image. e.g. [3][4]
* Etcd periodic local/remote backup?... maybe not in this chart day2 part, but definetly we need to support restoration from backup somewhere on init phase it backup is available.

Tests:
* Split test into test library and number for files with tests.
* Make it similar with go test maybe


[1] ipvs based vip
```
# Adding VIP Frontend
ipvsadm -A -t 127.0.0.1:6443 -s rr

# Adding VIP backends (Control Plane nodes)
ipvsadm -a -t 127.0.0.1:6443 -r 192.168.1.11:6443 -m
ipvsadm -a -t 127.0.0.1:6443 -r 192.168.1.12:6443 -m
ipvsadm -a -t 127.0.0.1:6443 -r 192.168.1.13:6443 -m
```

[2] iptables based vip
```
# example of 1 of 3 backends (see probability)
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 6443 \
  -m statistic --mode random --probability 0.33333 \
  -j DNAT --to-destination 192.168.1.11:6443
```

[3] containderd-native bins extraction
```
mkdir -p /tmp/img_mount
sudo ctr image mount <image_reference> /tmp/img_mount
cp /tmp/img_mount/path/to/file /path/on/host/
sudo ctr image unmount /tmp/img_mount
```
(there are some other ways for this)

[4] cri-o -native bins extraction
```
# from running container
PID=$(sudo crictl inspect --output json <container_id> | jq '.status.pid')
sudo cp /proc/$PID/root/path/to/file /host/path/

# or
sudo crictl exec <container_id> cat /path/to/file > /host/path/file

# or
ROOTFS=$(sudo crictl inspect --output json <container_id> | jq -r '.info.runtimeSpec.root.path')
sudo cp "$ROOTFS/path/to/file" /host/path/
```

[5] other snippets for bootstrap:

if you want to pass HELM/YQ env vars into the cloudinit script

```
YQ=yq HELM=helm HELM_ARGS="template kubeadm -f <your_value>.yaml" bash -c "\${HELM} \${HELM_ARGS} --set manifests.secret_bootstrap=true --set bootstrap.string_data=true | \${YQ} eval '. | select(.kind == \"Secret\" and .metadata.name == \"kubeadm-service-cbootstrap\") | .stringData[\"script\"]' | bash -s -- --pod-network-cidr=10.244.0.0/16"
```