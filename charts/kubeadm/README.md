# Kubeadm Day0 Chart

> *Take the Helm at Day 0*

This is not just a standard Helm chart — it is a **0-fat Day 0 chart**, designed to operate before Kubernetes even exists. It is a declarative tool that wraps, extends, and overrides [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) phases for cluster bootstrapping and upgrading.

## Key Capabilities

* **Day 0 / Day 1 (Bootstrap):** Declaratively generates custom bash scripts for `cloud-init` directly from `values.yaml` to execute `kubeadm init` and `kubeadm join` phases. The resulting scripts can run directly on the node or be passed as standard user-data payloads to cloud and bare-metal provisioners.
* **Day 2 (Reconfiguration & Upgrades):** Performs cluster reconfiguration and binary/component upgrades. When redeployed with updated `values.yaml`, it executes reconciliation logic to align the live cluster state with the target configuration.
* **Rebootstrap (Recovery & CA Rotation):** Puts the certificates of `values.yaml` on the nodes of an existing cluster again, whether its API works or not: an abrupt rotation of the CAs, a recovery from expired certificates. The reconcile waits meanwhile, the procedure can be rolled back from the backups.

The lifecycle of a node is **b-r-rb**: bootstrap, reconcile, rebootstrap. The node scripts run phase by phase (`--phases`, `--skip-phases`), so an orchestration drives them across the nodes: `overrides/reference/ssh-orchestration-ca.yaml` (the CAs only in the values, kubeadm generates the rest) and `ssh-orchestration-full.yaml` (the full PKI) are reference ones over ssh, tested by the gates.

## Architecture & Philosophy

Thanks to the `templates/lib/bundle` module, all chart outputs can be fully redefined or overridden directly via `values.yaml`. This provides the flexibility to adapt to many different infrastructure scenarios without modifying the chart's code, while maintaining strict alignment between Day 1 (bootstrap) and Day 2 (reconfiguration/upgrades) to prevent configuration drift.

Since the primary goal is to bootstrap Kubernetes precisely from zero (bare OS with no prior configuration) up to a fully functional Kubernetes API, and to maintain this configuration over time, the chart is intentionally kept as minimalistic as possible: its sole purpose is to solve the chicken-and-egg bootstrapping problem cleanly.

The chicken and the egg are untied by Helm itself: it renders templates on the client, without a cluster. `helm template` turns the values into the bootstrap and rebootstrap scripts before the Kubernetes API exists (or when it is down), and the same chart, installed into the cluster it has just bootstrapped, runs the reconcile. One chart and one set of values for every stage of the lifecycle, so bootstrap and reconcile can't drift apart.

## Tools

The chart carries its own helper tools, so a deployment needs nothing but `helm` and the chart. They are rendered into the `kubeadm-service-tools` Secret with `--set manifests.secret_tools=true` and can be redefined in `bundle.tpl` like any other template.

### `gen-pki.sh`

Generates the Kubernetes, etcd and front proxy CAs and the service account key as a values override (`values-pki.yaml`), kubeadm generates the rest of the PKI on the nodes. Requires `openssl`.

```bash
helm template kubeadm --set manifests.secret_tools=true \
  | sed -n 's/^ *gen-pki.sh: *\(.*\)/\1/p' | base64 -d \
  | bash -s -- --out-file ./secrets/values-pki.yaml --days 3650
```

The tool is rendered with the defaults of the chart: the PKI doesn't depend on the other values. The deployment then takes the generated values together with your own ones:

```bash
helm template kubeadm -f values.yaml -f ./secrets/values-pki.yaml ...
```

This is how the gate deploys the cluster (`ssh-bootstrap.sh` of `overrides/reference/ssh-orchestration-ca.yaml`).

## Checks

The checks are a sanity check of the cluster: Kubernetes works and runs the version of the values.

On the node, the `checks` phase checks what the node itself needs: at the end of the bootstrap script (`checks.bootstrap`) that the API is reachable through `kubeconfig.controlPlaneEndpoint`, and in the reconcile before the anchor becomes ready (`checks.reconcile`) the first pass of the haproxy VIP reconcile. A failing node fails its bootstrap, or its anchor doesn't become ready and stops the rolling update. The static pods check their own liveness. One line per check:

```
check OK api https://127.0.0.1:6553/livez
check FAIL vip the haproxy config can't follow the apiservers (see above)
check SKIP vip the node has no haproxy VIP
```

`helm test` (`manifests.helm_test`) checks the whole cluster from a control plane node, with the host `kubectl` and `/etc/kubernetes/admin.conf` through `chroot` as the anchor does: the anchors are rolled out (so the node checks passed everywhere), the nodes are ready, the control plane static pods are ready, the kubelets and the control plane run `cluster_config.kubernetesVersion`, and etcd has a member for every etcd pod.

```bash
helm test kubeadm --logs
```

When the chart is applied with `kubectl` (e.g. `helm template | kubectl apply`), render it with `--skip-tests`: `kubectl` ignores the hook annotations and would create the test pod at once. The gate runs the test pod separately, see `tools/deployment/kubeadm/045-helm-test.sh`.

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

More examples are here [1].

## Roadmap

The project is under development. Below is the planned roadmap and feature wishlist (subject to iteration).

### Next, in this order
#### 1. Linking
The last library of the chart.

- **Dynamic Module Linking (experimental):** every bash function of the node scripts is registered in a map with the names of the functions it calls; the values list the phases a script supports, and its shared library is linked from them by the dependencies, like object files into a binary: only what the phases need, an undefined function fails the rendering, `bundle.tpl` can replace or add functions. A test checks the declared dependencies against the calls.
  - *Objects:* the modules of `templates/phases` (the built-in ones listed as now, the new ones of `bundle.tpl` found by their path), all in one format, all processed; `main` and the phases snippet are always in.
  - *Symbols:* functions and variables (the globals like `KUBEADM_ANNOTATION`), both with their dependencies; the same name twice fails the rendering.
  - *Order:* by the dependencies (the ones everything depends on first), the name for the ties: the same output on every rendering, the hashes of the scripts trigger the rollouts of the anchors.
  - *Entry points:* a phase is a function too; the bootstrap and the rebootstrap scripts link from the functions of their phases (the list of the values), the reconcile one from the set of the functions its body calls.
  - *For the deployment engineers:* a section of this README with an example of replacing and adding a function through `bundle.tpl`; clear messages of the rendering (an undefined or a duplicate symbol, with the module and the function referring to it) and a way to see what is linked and why (e.g. the linked symbols in a comment of the rendered script).
  - *Instead of the libraries per script:* `*_rebootstrap_lib` (backup, restore, the certificates of kubeadm) exist only to keep them out of the bootstrap script; linked, they are symbols of their modules the bootstrap phases don't depend on.
#### 2. Idempotent reconcile
Carefully, with crash and restart tests (its steps are explicit once linked).

- **Idempotent Reconcile State Machine:** Ensure step-level idempotency in `reconcile.sh` so that upon a crash loop, execution resumes exactly from the failed step.
#### 3. kube-vip
A new phase (a test of the linking too).

- **External control plane VIP (`kube-vip`):** a different task than the node-local balancer: a floating VIP for clients outside the cluster (admin kubeconfigs, a parent cluster, Armada), as a static pod on control plane nodes.
#### 4. A cluster from a parent one
An override and a gate.

- **No-Pivot Mode:** management remains on the parent cluster instead of pivoting to self-hosted child management. The credentials of the parent exist (`secret_ca_tls`, `secret_admin_tls`, `cert_manager_admin`); left: a gate deploying a cluster from a parent one, with a cloud-init simulation as the provisioner.
#### 5. Hosted control plane
A big override and a gate.

A hosted control plane cluster: the control plane runs as pods on the parent cluster, the target cluster has worker nodes only. A moderate amount of work assembled from standard pieces, without changes to the core of the chart:
- **Profile, not core code:** the control plane templates ship as files in the chart, disabled by default, and a profile values file (e.g. `profiles/hosted-control-plane.yaml`) wires them in through `bundle.manifests` and disables what isn't needed (masters anchor, VIP).
- **Control plane on the parent:** `kube-apiserver`, `kube-controller-manager` and `kube-scheduler` Deployments, the API exposed through a LoadBalancer, NodePort or Ingress with SNI passthrough. Upgrades become rollouts on the parent instead of `kubeadm upgrade node`.
- **Datastore:** `kine` (SQL backend, lighter, fits small and edge clusters) or an etcd StatefulSet for bigger ones.
- **Konnectivity:** the server as a sidecar of the apiserver (`EgressSelectorConfiguration`), the agents as static pods on the workers, like the HAProxy one, authenticated with mTLS certificates delivered by the chart. Needed for `logs`, `exec`, webhooks and metrics from the parent to the nodes.
- **PKI:** all certificates pregenerated or issued by cert-manager (CA `Issuer`), the apiserver certificate covering the external endpoint.
- **Cluster-side kubeadm phases:** `upload-config`, `bootstrap-token` and the `coredns`/`kube-proxy` addons run by a Job on the parent against the hosted API, so the workers join with the usual `kubeadm join` and are reconciled by the workers anchor.

### Later
- **Phase Validation & Cross-Alignment:** Validate CLI arguments against `kubeadm` phase configurations to warn if parameters contradict each other across phases.
- **Etcd Disaster Recovery:** Support `etcd` restoration from backup during the `init` phase if backup artifacts are available (enabling full cluster state restoration from zero).
- **Addon Patching References:** Provide standard patterns and examples for patching core add-ons (`kube-proxy`, `CoreDNS`) directly via `kubeadm` phase overrides.

### VIP Backends
- **Node-local API load balancer:** HAProxy stays the only built-in implementation: proven in Airship, and the control plane endpoints change rarely, so dynamically reconfigured proxies (Envoy, Traefik) bring nothing. Kernel-space variants (iptables, IPVS, nftables) are not planned: they have no health checks of their own and need extra care for a `127.0.0.1` VIP (SNAT, `route_localnet`); whoever needs one can provide it through `bundle.tpl`.
- **VIP mode is a day 0 decision:** the reconcile only follows the backends and the configuration of the VIP the node was bootstrapped with (it's on if the bootstrap wrote `haproxy.cfg`). Enabling, disabling or switching the VIP type on a live cluster is a migration: `controlPlaneEndpoint` in `kubeadm-config`, the server address in the kubeconfigs of every node, the apiserver certificate SANs and the order of the nodes. To be done as a dedicated, carefully ordered scenario, like the Airship to kubeadm migration in the reconcile.

### PKI Lifecycle & Certificate Management
- **Automated & Manual Cert Rotation:** Support certificate rotation using the existing CA via scheduled `CronJob` instances or manual `Job` triggers.
- **Seamless CA Migration:** an intermittent dual-CA trust period with dual-signed / fallback verification. The abrupt one is the rebootstrap.
- **Expiry Warnings:** The reconcile loop checks the certificates (`kubeadm certs check-expiration` on control plane nodes, `openssl` for the kubelet certificates) and logs a warning in a stable one-line format (e.g. `WARNING cert-expiry file=... not_after=... days_left=...`) when one expires sooner than a threshold from `values.yaml`, so a log collector such as fluentd can pick it up. A warning, not a failure: it doesn't block the reconcile.

### Testing & Verification
- **Modular Test Library:** Refactor test suites into a structured Bash test library with individual test specs (matching Go-like test signatures and execution flows).
- **Helm Test & Gate Verification:** done, see [Checks](#checks). Left:
  - **Switching phases:** the checks are a phase of the node scripts (`--skip-phases checks`), but still switched on at render time with the flags in `checks`.
  - **Armada based gates:** `test.enabled` of the `ArmadaChart` in the aircat and aircruiser gates.
  - **Hosted control plane:** the profile replaces the control plane test (Deployments on the parent cluster, kubeconfig from a Secret, datastore and konnectivity checks), the worker checks stay as is.

[1] other snippets for bootstrap:

if you want to pass HELM/YQ env vars into the cloudinit script

```
YQ=yq HELM=helm HELM_ARGS="template kubeadm -f <your_value>.yaml" bash -c "\${HELM} \${HELM_ARGS} --set manifests.secret_bootstrap=true --set bootstrap.string_data=true | \${YQ} eval '. | select(.kind == \"Secret\" and .metadata.name == \"kubeadm-service-cbootstrap\") | .stringData[\"script\"]' | bash -s -- --pod-network-cidr=10.244.0.0/16"
```