# Kubeadm Day0 Chart

> *Take the Helm at Day 0*

This is not just a standard Helm chart — it is a **0-fat Day 0 chart**, designed to operate before Kubernetes even exists. It is a declarative tool that wraps, extends, and overrides [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) phases for cluster bootstrapping and upgrading.

## Key Capabilities

* **Day 0 / Day 1 (Bootstrap):** Declaratively generates custom bash scripts for `cloud-init` directly from `values.yaml` to execute `kubeadm init` and `kubeadm join` phases. The resulting scripts can run directly on the node or be passed as standard user-data payloads to cloud and bare-metal provisioners.
* **Day 2 (Reconfiguration & Upgrades):** Performs cluster reconfiguration and binary/component upgrades. When redeployed with updated `values.yaml`, it executes reconciliation logic to align the live cluster state with the target configuration.

## Architecture & Philosophy

Thanks to the `templates/lib/bundle` module, all chart outputs can be fully redefined or overridden directly via `values.yaml`. This provides the flexibility to adapt to many different infrastructure scenarios without modifying the chart's code, while maintaining strict alignment between Day 1 (bootstrap) and Day 2 (reconfiguration/upgrades) to prevent configuration drift.

Since the primary goal is to bootstrap Kubernetes precisely from zero (bare OS with no prior configuration) up to a fully functional Kubernetes API, and to maintain this configuration over time, the chart is intentionally kept as minimalistic as possible: its sole purpose is to solve the chicken-and-egg bootstrapping problem cleanly.

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

This is how the gate deploys the cluster (`tools/deployment/kubeadm/010-generate-ca.sh`).

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

The project is under development. Below is the planned roadmap and feature wishlist (subject to iteration):

### Kubeadm & Lifecycle Engine
- **Phase Validation & Cross-Alignment:** Validate CLI arguments against `kubeadm` phase configurations to warn if parameters contradict each other across phases.
- **Etcd Disaster Recovery:** Support `etcd` restoration from backup during the `init` phase if backup artifacts are available (enabling full cluster state restoration from zero).
- **Bootstrap-to-Reconcile Handoff:** Implement node annotation markers during `bootstrap.sh` execution so the `reconcile.sh` anchor skips redundant initialization steps and picks up live state safely.
- **Idempotent Reconcile State Machine:** Ensure step-level idempotency in `reconcile.sh` so that upon a crash loop, execution resumes exactly from the failed step.
- **Pre-CNI Deployment Readiness:** Relax and tune pod tolerations so the chart and its anchor pods can be applied cleanly before a CNI plugin is present on the cluster.
- **No-Pivot Mode:** Support external control-plane orchestration where management remains on the parent cluster (sending `kubeconfig` back) instead of pivoting to self-hosted child management.
- **Addon Patching References:** Provide standard patterns and examples for patching core add-ons (`kube-proxy`, `CoreDNS`) directly via `kubeadm` phase overrides.

### Extensibility & Modular Architecture
- **Dynamic Module Linking:** Implement a dynamic linking mechanism for chart modules to support imperative CLI extensions and phase-skipping for chart-provided phases.
- **Custom Payload Overrides:** Allow users to completely replace the main execution script body (beyond shared library functions) via `values.yaml`.
- **Modular CLI Helpers (`tools/`):** Embed non-interactive Bash tools (such as `gen-pki.sh`) to pre-generate complex, isolated `values-*.yaml` fragments (e.g., full PKI catalogs and SAN matrices) without manual YAML manipulation.
- **Self-Bootstrapping Demo Profile (`values.demo.yaml`):** An optional onboarding pattern designed for rapid evaluation and reference architectures. Without adding any code bloat to the core chart, this demo override embeds an interactive setup workflow into the initial rendered script (`helm template -f values.demo.yaml | bash`) to guide node parameters, invoke `gen-pki.sh`, apply targets, and even launch `k9s` upon readiness.

### Anchor Evolution & VIP Backends
- **VIP reconsiliation:** support calling vip evaluation/update code called in the reconsile sleep loop.
- **Expanded VIP Implementation:** Extend the anchor container beyond HAProxy to support alternative VIP backends via a unified interface:
  - **`kube-vip`:** Static pod or in-cluster daemon support.
  - **IPVS-based VIP:**
    ```bash
    # Adding VIP Frontend
    ipvsadm -A -t 127.0.0.1:6443 -s rr

    # Adding VIP backends (Control Plane nodes)
    ipvsadm -a -t 127.0.0.1:6443 -r 192.168.1.11:6443 -m
    ipvsadm -a -t 127.0.0.1:6443 -r 192.168.1.12:6443 -m
    ipvsadm -a -t 127.0.0.1:6443 -r 192.168.1.13:6443 -m
    ```
  - **IPTables-based VIP:**
    ```bash
    # Example for 1-of-3 backends using statistical probability
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 6443 \
      -m statistic --mode random --probability 0.33333 \
      -j DNAT --to-destination 192.168.1.11:6443
    ```

### PKI Lifecycle & Certificate Management
- **Automated & Manual Cert Rotation:** Support certificate rotation using the existing CA via scheduled `CronJob` instances or manual `Job` triggers.
- **CA Migration Strategies:** Handle CA transitions across two distinct operational models:
  - *Seamless:* Intermittent dual-CA trust period with dual-signed / fallback verification.
  - *Abrupt:* Synchronous node-wide replacement with coordinated `kubelet` restarts via host service triggers.

### Testing & Verification
- **Modular Test Library:** Refactor test suites into a structured Bash test library with individual test specs (matching Go-like test signatures and execution flows).
- **Helm Test & Gate Verification:** Integrate `helm test` targets leveraging lightweight sanity checks extracted from CI gates.


[1] other snippets for bootstrap:

if you want to pass HELM/YQ env vars into the cloudinit script

```
YQ=yq HELM=helm HELM_ARGS="template kubeadm -f <your_value>.yaml" bash -c "\${HELM} \${HELM_ARGS} --set manifests.secret_bootstrap=true --set bootstrap.string_data=true | \${YQ} eval '. | select(.kind == \"Secret\" and .metadata.name == \"kubeadm-service-cbootstrap\") | .stringData[\"script\"]' | bash -s -- --pod-network-cidr=10.244.0.0/16"
```