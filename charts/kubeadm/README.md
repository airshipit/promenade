# Kubeadm Day0 Chart

> *Take the Helm at Day 0*

This is not just a standard Helm chart — it is a **0-fat Day 0 chart**, designed to operate before Kubernetes even exists. It is a declarative tool that wraps, extends, and overrides [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) phases for cluster bootstrapping and upgrading.

## Key Capabilities

* **Day 0 / Day 1 (Bootstrap):** Declaratively generates custom bash scripts for `cloud-init` directly from `values.yaml` to execute `kubeadm init` and `kubeadm join` phases. The resulting scripts can run directly on the node or be passed as standard user-data payloads to cloud and bare-metal provisioners.
* **Day 2 (Reconfiguration & Upgrades):** Performs cluster reconfiguration and binary/component upgrades. When redeployed with updated `values.yaml`, it executes reconciliation logic to align the live cluster state with the target configuration.
* **Rebootstrap (Recovery & CA Rotation):** Puts the certificates of `values.yaml` on the nodes of an existing cluster again, whether its API works or not: an abrupt rotation of the CAs, a recovery from expired certificates. The reconcile waits meanwhile, the procedure can be rolled back from the backups.

The lifecycle of a node is **b-r-rb**: bootstrap, reconcile, rebootstrap. The node scripts are libraries of phases: by default they run their list of phases, the command line gives the phases their arguments (`-- <phase> <arguments>`) or, with `--run`, names the phases to run in its order, so an orchestration drives them across the nodes: `overrides/reference/ssh-orchestration-ca.yaml` (the CAs only in the values, kubeadm generates the rest) and `ssh-orchestration-full.yaml` (the full PKI) are reference ones over ssh, tested by the gates.

## Architecture & Philosophy

The chart bootstraps Kubernetes from zero, a bare OS without any prior configuration, up to a working Kubernetes API, and keeps this configuration over time. It is kept as small as possible: its only purpose is to solve the chicken-and-egg problem of the bootstrap cleanly.

### One chart for the whole lifecycle

Helm renders the templates on the client, without a cluster. `helm template` turns the values into the bootstrap and rebootstrap scripts before the Kubernetes API exists, or while it is down. The same chart, installed into the cluster it has just bootstrapped, runs the reconcile: its anchor DaemonSets apply the values on every node. One chart and one set of values serve every stage of the lifecycle, so the bootstrap and the reconcile can't drift apart.

The chart carries its own helper tools too, so a deployment needs nothing but `helm` and the chart (see [Tools](#tools)).

### Node scripts

The bash code of the nodes lives in the modules of `templates/phases/modules`. A module is a library of functions. Every function is a symbol with the list of the symbols it needs, and a script is linked from the functions it calls like a binary from object files (`templates/lib/_linker.tpl`, see [Modules](#modules)), so it carries only the code it uses. A function returning a result ends with `_rc`, e.g. `kubelet_sync_rc` returns 0 if it changed the files, 1 if not and more than 1 on errors.

There are two node scripts:

- **run_phases** (`templates/bin/_run_phases.sh.tpl`) runs the phases of a profile, `phase_runner.profiles.<phase_runner.profile>`. The `bootstrap` profile makes a node a node of the cluster, the `rebootstrap` one puts the certificates of the values on the nodes of an existing cluster again. A phase is a function of a module. The command line gives a phase its arguments (`-- <phase> <arguments>`), or with `--run` runs only the named phases in its order, so an orchestration can drive the nodes step by step. A phase written as `+<phase>` runs only when the command line names it. When an `_rc` function runs as a phase, 1 isn't a failure.
- **reconcile** (`templates/bin/_reconcile.sh.tpl`) runs in the anchor pods. Its `reconcile` function makes one pass: it syncs the files of the chart, applies the changes (kubeadm, the restart of kubelet) and runs the node checks, then the anchor becomes ready. After that its main loop checks the node every `anchor.reconcile.period` seconds. When a change needs a new pass (e.g. the configuration changed), the script ends, the pod restarts and a new pass begins.

The reconcile is an orchestrator over the modules: `reconcile` decides what to call, and `anchor.reconcile` holds its switches. It is a module itself only to be linked the same way.

### Modules

A module is a directory of `templates/phases/modules` with its `_.sh.tpl`. `templates/phases/_modules.tpl` lists the files of the modules: it renders each of them and gives the text to the linker (`linker_symbols_from_sh`). A module may have more files in the list, e.g. the reconcile module has `_lib.sh.tpl` too. A file given as `(list "<path>" false)` is only rendered, `linker_symbols_from_sh` isn't called for it. The other files of a module are snippets the module uses, e.g. a static pod or a configuration file for the nodes.

`_.sh.tpl` is a bash file with template code, rendered with `(tuple $envAll $k8sConfDict)` as the modules are. It has three parts:

1. the template code of the module, if it has any: the files it puts into the archives of the nodes, the symbols it generates (e.g. `fsgroup_<group>_sync_rc`);
2. comments about the module, they aren't linked: `_modules.tpl` checks that there is nothing else there and fails with the path of the file otherwise (code there would be lost, a `#!needs:` there would belong to no symbol);
3. the functions and the global variables of the module. Each of them starts with a `#!define: <name>` line, its `#!needs: <name>, <name>...` lines name the symbols it uses. The text till the next `#!define:` is its body.

```bash
#!define: backup_exists_rc
# 0 while backup.dir exists: the procedure isn't over
backup_exists_rc() {
  [ -e "${ROOTFS}{{ $envAll.Values.backup.dir }}" ]
}

#!define: group_dir_backup
#!needs: backup_files, group_dir_files
# copies the files of the directory the group syncs to the backup directory
group_dir_backup() {
  backup_files "$5" $(group_dir_files "$1" "$2" "$3" "$4")
}
```

The file is rendered first, then the linker reads the directives. So the values are in the bodies as in any template, and a `#!needs:` line can be rendered by a condition: the symbol is linked only when the code calling it is (conditional linking). E.g. with `anchor.reconcile.vip` off the reconcile script has neither the call of `vip_reconcile` nor the functions it needs. `#!needs:` can be anywhere in a line, e.g. after the call it is for, the linker cuts it off till the end of the line:

```bash
{{- if $envAll.Values.anchor.reconcile.vip }}
    vip_reconcile || true #!needs: vip_reconcile
{{- end }}
```

`#!define:` starts a line. The linker doesn't read the bodies: a call without its `#!needs:` shows up on the node only, as "command not found". The template code between the symbols is written as `{{- ... }}`, without the trim on the right: it would join the next `#!define:` to the line before it.

### Customization

The templates of the chart can be redefined in `values.yaml` without changing the chart (`templates/lib/bundle`):

- `bundle.tpl."<path>"` replaces the template `<path>`, e.g. `templates/phases/modules/reconcile/_.sh.tpl` for another reconcile;
- `bundle.tpl."<path>.patch"` is a strategic merge patch of a template of a Kubernetes object: the anchor DaemonSets, the test pod, the haproxy static pod and the kubelet restart job;
- `templates/phases/_modules.tpl` is the list of the files of the modules, its comment describes how to switch a module off;
- `binaries.sync.kubernetes`, `binaries.sync.cri` and `binaries.sync.etcd` are the functions (with their `#!define:` and `#!needs:`) which install the Kubernetes binaries, the container runtime and etcdutl and etcdctl, so they can come from a URL, from distribution packages or from a local repository (see `overrides/test/binaries-apt.yaml`).

### Checks

The checks are a sanity check of the cluster: Kubernetes works and runs the version of the values. They are a part of the lifecycle:

- The bootstrap script ends with the `check_run` phase: the API is reachable through `kubeconfig.controlPlaneEndpoint` (`check_api`). A failing node fails its bootstrap.
- The reconcile runs `check_run` before the anchor becomes ready (`anchor.reconcile.checks`). The VIP of the node follows the apiservers of the cluster (`vip_check`, with `anchor.reconcile.vip`), a node bootstrapped without a VIP skips it. The apiserver, etcd and kubelet of the node serve the certificates of their files (`certs_check`): they reload them after a sync, `checks.attempts` gives them the time. A failing node doesn't become ready and stops the rolling update of the anchors.
- `helm test` (`manifests.helm_test`) checks the whole cluster from a control plane node, with the host `kubectl` and `/etc/kubernetes/admin.conf` through `chroot` as the anchor does: the anchors are rolled out (so the node checks passed everywhere), the nodes are ready, the control plane static pods are ready, the kubelets and the control plane run `cluster_config.kubernetesVersion`, and etcd has a member for every etcd pod.

The static pods check their own liveness.

### VIP Backends
- **Node-local API load balancer:** HAProxy stays the only built-in implementation: proven in Airship, and the control plane endpoints change rarely, so dynamically reconfigured proxies (Envoy, Traefik) bring nothing. Kernel-space variants (iptables, IPVS, nftables) are not planned: they have no health checks of their own and need extra care for a `127.0.0.1` VIP (SNAT, `route_localnet`); whoever needs one can provide it through `bundle.tpl`.
- **VIP mode is a day 0 decision:** the reconcile only follows the backends and the configuration of the VIP the node was bootstrapped with (the bootstrap writes it to `/etc/kubernetes/kubeadm/addons/vip`, the reconcile writes the VIP of the values there on the nodes bootstrapped before). Enabling, disabling or switching the VIP type on a live cluster is a migration: `controlPlaneEndpoint` in `kubeadm-config`, the server address in the kubeconfigs of every node, the apiserver certificate SANs and the order of the nodes. To be done as a dedicated, carefully ordered scenario, like the Airship to kubeadm migration in the reconcile.

## Usage

### Extracting the Script of a Profile

The script of a profile (`phase_runner.profile`, `bootstrap` by default) is a standalone bash script, so a provisioner can pass it as user data (e.g. cloud-init) or it can be run on the node by hand. It is in the `script` key of the phase-runner Secret, rendered with `--set manifests.secret_phase_runner=true`. With per-node data in the values there is a Secret for every node, `kubeadm-service-phase-runner-<node>`. `--set phase_runner.nodename=<node>` renders only the Secret of that node, named `kubeadm-service-phase-runner`, and no other manifests, so the script is easy to cut out:

```bash
# with yq
helm template kubeadm -f values.yaml --set manifests.secret_phase_runner=true --set phase_runner.nodename=node0 \
  | yq eval 'select(.kind == "Secret" and .metadata.name == "kubeadm-service-phase-runner") | .data["script"] | @base64d'

# with sed and base64 only
helm template kubeadm -f values.yaml --set manifests.secret_phase_runner=true --set phase_runner.nodename=node0 \
  | sed -n 's/^ *script: *\(.*\)/\1/p' | base64 -d
```

`--set phase_runner.string_data=true` puts the script into the Secret as plain text, which is handy for debugging. Pipe the script into `bash -s -- <arguments>` to run it with the arguments of its phases (see [Node scripts](#node-scripts)), e.g. `bash -s -- -- kubeadm_run join ...` on a joining node.

### Tools

The tools are rendered into the `kubeadm-service-tools` Secret with `--set manifests.secret_tools=true` and can be redefined in `bundle.tpl` like any other template.

#### `gen-pki.sh`

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

### Running the Checks

On the node, `check_run` runs the given checks and fails if any of them failed (see [Checks](#checks)). Every check prints one line:

```
check OK api https://127.0.0.1:6553/livez
check OK vip the haproxy VIP follows the apiservers
check OK certs 127.0.0.1:6443 serves /etc/kubernetes/pki/apiserver.crt
check SKIP vip the node has no VIP
```

The cluster checks:

```bash
helm test kubeadm --logs
```

When the chart is applied with `kubectl` (e.g. `helm template | kubectl apply`), render it with `--skip-tests`: `kubectl` ignores the hook annotations and would create the test pod at once. The gate runs the test pod separately, see `tools/deployment/kubeadm/045-helm-test.sh`.

### Restoring etcd from a Snapshot

A lost control plane can be bootstrapped again with the etcd of a snapshot (`etcdctl snapshot save`); taking and keeping the snapshots isn't the job of the chart. On the first control plane node the `+etcd_restore <snapshot>` phase of the bootstrap script restores the snapshot before `kubeadm_run` (with `--run`): the member gets the name and the peer URL kubeadm gives it, and `kubeadm init` starts etcd with the restored data. `kubeadm init` needs `--ignore-preflight-errors=DirAvailable--var-lib-etcd` then. The other control plane nodes join it as usual. etcdutl comes from `binaries.sync.etcd` (`binaries.etcd.version`), or the one on the node is used. The `+binary_etcd_sync_rc` phase installs etcdutl and etcdctl on the node alone too, e.g. for the snapshots.

With the same PKI the workers reconnect: their certificates and the service account tokens of the snapshot stay valid. The snapshot brings back the Node objects as they were, and `kubeadm join` refuses a Ready one, so the Node objects of the other control plane nodes are deleted before they join.

`ssh-bootstrap.sh --restore <snapshot>` of `overrides/reference/ssh-orchestration-ca.yaml` does all of this, the gate tests it (`tools/deployment/kubeadm-ssh/047-ssh-etcd-restore.sh`).

## Roadmap

The project is under development. Below is the planned roadmap and feature wishlist (subject to iteration).

### Next, in this order
#### 1. Idempotent reconcile
Carefully, with crash and restart tests (its steps are explicit once linked).

- **Idempotent Reconcile State Machine:** Ensure step-level idempotency in `reconcile.sh` so that upon a crash loop, execution resumes exactly from the failed step.
#### 2. kube-vip
A new phase (a test of the linking too).

- **External control plane VIP (`kube-vip`):** a different task than the node-local balancer: a floating VIP for clients outside the cluster (admin kubeconfigs, a parent cluster, Armada), as a static pod on control plane nodes.
#### 3. Phase validation, addon patching
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
