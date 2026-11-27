# Kubeadm Day0 Chart

> *Take the Helm at Day 0*

This is not just a standard Helm chart — it is a **0-fat Day 0 chart**, designed to operate before Kubernetes even exists. It is a declarative tool that wraps, extends, and overrides [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) phases for cluster bootstrapping and upgrading.

## Key Capabilities

* **Day 0 / Day 1 (Bootstrap):** generates a bash script from `values.yaml` which runs `kubeadm init` or `kubeadm join` on a node, by hand or as user data of a provisioner (e.g. cloud-init).
* **Day 2 (Reconfiguration & Upgrades):** installed into the cluster, the chart keeps the nodes in sync with `values.yaml`. A new `cluster_config.kubernetesVersion` upgrades the cluster with the rollout of the anchors: `kubeadm upgrade node` on the control plane nodes, then the binaries and kubelet on every node, drained by default; the workers wait until all the apiservers run the new version.
* **Rebootstrap (Abrupt CA Rotation):** puts the certificates of `values.yaml` on all the nodes again, the API alive or not (e.g. an expired CA), and can be rolled back from the backups.

## How It Works

`helm template` turns the values into the phase-runner scripts of the nodes before the Kubernetes API exists, or while it is down. The same chart installed into the cluster runs the reconcile in its anchor DaemonSets on every node. One chart and one set of values serve the whole lifecycle, so the bootstrap and the reconcile can't drift apart.

The phase-runner script runs the phases of a profile, `bootstrap` or `rebootstrap`, and its command line lets an orchestration drive the nodes step by step. `overrides/reference/orchestration-ssh-ca.yaml` (the CAs only in the values) and `overrides/reference/orchestration-ssh-full.yaml` (the full PKI) are reference orchestrations over ssh, tested by the gates.

## Usage

### Extracting the Script of a Profile

The script is in the `script` key of the phase-runner Secret, rendered with `--set manifests.secret_phase_runner=true`. `--set phase_runner.nodename=<node>` renders only the Secret of that node, named `kubeadm-service-phase-runner`, and no other manifests:

```bash
# with yq
helm template kubeadm -f values.yaml --set manifests.secret_phase_runner=true --set phase_runner.nodename=node0 \
  | yq eval 'select(.kind == "Secret" and .metadata.name == "kubeadm-service-phase-runner") | .data["script"] | @base64d'

# with sed and base64 only
helm template kubeadm -f values.yaml --set manifests.secret_phase_runner=true --set phase_runner.nodename=node0 \
  | sed -n 's/^ *script: *\(.*\)/\1/p' | base64 -d
```

Pipe the script into `bash -s -- <arguments>`, e.g. `bash -s -- -- kubeadm_run join ...` on a joining node. `--set phase_runner.profile=rebootstrap` gives the script of the rebootstrap.

### More

- **`gen-pki.sh`:** generates the CAs as a values override (`--set manifests.secret_tools=true`).
- **`helm test kubeadm --logs`:** checks the whole cluster; render with `--skip-tests` for `kubectl apply`.
- **`ssh-bootstrap.sh --restore <snapshot>`:** bootstraps a lost control plane again from an etcd snapshot.
- **VIP:** haproxy on every node, a day 0 decision; switching it later is a migration.

## Roadmap

The project is under development. Below is the planned roadmap and feature wishlist (subject to iteration).

### Next, in this order
#### 1. kube-vip
A new phase (a test of the linking too).

- **External control plane VIP (`kube-vip`):** a different task than the node-local balancer: a floating VIP for clients outside the cluster (admin kubeconfigs, a parent cluster, Armada), as a static pod on control plane nodes.
#### 2. Phase validation, addon patching
- **Phase Validation & Cross-Alignment:** Validate CLI arguments against `kubeadm` phase configurations to warn if parameters contradict each other across phases.
- **Addon Patching References:** Provide standard patterns and examples for patching core add-ons (`kube-proxy`, `CoreDNS`) directly via `kubeadm` phase overrides.

### PKI Lifecycle & Certificate Management
- **Automated & Manual Cert Rotation:** Support certificate rotation using the existing CA via scheduled `CronJob` instances or manual `Job` triggers.
- **Seamless CA Migration:** an intermittent dual-CA trust period with dual-signed / fallback verification. The abrupt one is the rebootstrap.
- **Expiry Warnings:** The reconcile loop checks the certificates (`kubeadm certs check-expiration` on control plane nodes, `openssl` for the kubelet certificates) and logs a warning in a stable one-line format (e.g. `WARNING cert-expiry file=... not_after=... days_left=...`) when one expires sooner than a threshold from `values.yaml`, so a log collector such as fluentd can pick it up. A warning, not a failure: it doesn't block the reconcile.

### Later
A separate piece of work, not planned now.

#### A cluster from a parent one
An override and a gate.

- **No-Pivot Mode:** management remains on the parent cluster instead of pivoting to self-hosted child management. The credentials of the parent exist (`secret_ca_tls`, `secret_admin_tls`, `cert_manager_admin`); left: a gate deploying a cluster from a parent one, with a cloud-init simulation as the provisioner.
#### Hosted control plane
A big override and a gate.

A hosted control plane cluster: the control plane runs as pods on the parent cluster, the target cluster has worker nodes only. A moderate amount of work assembled from standard pieces, without changes to the core of the chart:
- **Profile, not core code:** the control plane templates ship as files in the chart, disabled by default, and a profile values file (e.g. `profiles/hosted-control-plane.yaml`) wires them in through `bundle.manifests` and disables what isn't needed (masters anchor, VIP).
- **Control plane on the parent:** `kube-apiserver`, `kube-controller-manager` and `kube-scheduler` Deployments, the API exposed through a LoadBalancer, NodePort or Ingress with SNI passthrough. Upgrades become rollouts on the parent instead of `kubeadm upgrade node`.
- **Datastore:** `kine` (SQL backend, lighter, fits small and edge clusters) or an etcd StatefulSet for bigger ones.
- **Konnectivity:** the server as a sidecar of the apiserver (`EgressSelectorConfiguration`), the agents as static pods on the workers, like the HAProxy one, authenticated with mTLS certificates delivered by the chart. Needed for `logs`, `exec`, webhooks and metrics from the parent to the nodes.
- **PKI:** all certificates pregenerated or issued by cert-manager (CA `Issuer`), the apiserver certificate covering the external endpoint.
- **Cluster-side kubeadm phases:** `upload-config`, `bootstrap-token` and the `coredns`/`kube-proxy` addons run by a Job on the parent against the hosted API, so the workers join with the usual `kubeadm join` and are reconciled by the workers anchor.
- **Checks:** the profile replaces the control plane test (Deployments on the parent cluster, kubeconfig from a Secret, datastore and konnectivity checks), the worker checks stay as is.
