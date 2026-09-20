# k0s Kubernetes Distribution - Comprehensive Research

> Sources: Official documentation at docs.k0sproject.io/stable/ (August 2026)
> Note: Two pages returned 404: `/rbac/` (use `/user-management/` instead), `/performance/` (no dedicated page exists)

---

## 1. Architecture Overview

### Packaging
- **Single self-extracting binary** that embeds all Kubernetes binaries
- Statically compiled, no OS-level dependencies
- No RPMs, dependencies, snaps, or OS-specific packaging required
- Single package for all operating systems
- Full version control for each dependency

### Control Plane
- k0s acts as the **process supervisor** for all control plane components
- **No container engine or kubelet running on controllers by default** (workloads cannot be scheduled onto controllers)
- Components run as "naked" processes, not containers
- No container runtime needed on controller nodes

### Storage/Datastore
- Default: **etcd** (k0s manages full lifecycle of elastic etcd cluster)
- Also supports via [kine](https://github.com/k3s-io/kine): MySQL, PostgreSQL, SQLite, dqlite
- k0s **cannot shrink etcd cluster** - must manually remove node from etcd before shutting down controller
- When joining new controller with `k0s controller "long-join-token"`, k0s auto-adjusts etcd membership

### Worker Node
- Default CRI: **containerd** as high-level runtime, **runc** as low-level runtime
- Custom CRI runtimes supported
- Runs as naked processes on worker node

---

## 2. System Requirements

### Minimum Requirements

| Role | Memory (RAM GB) | vCPUs |
|------|-----------------|-------|
| Controller node | 1 | 1 |
| Worker node | 0.5 | 1 |
| Controller + worker | 1 | 1 |

### Controller Node Scaling Recommendations

| Workers | Pods | RAM (GB) | vCPU |
|---------|------|----------|------|
| 10 | 1,000 | 1-2 | 1-2 |
| 50 | 5,000 | 2-4 | 2-4 |
| 100 | 10,000 | 4-8 | 2-4 |
| 500 | 50,000 | 8-16 | 4-8 |
| 1,000 | 100,000 | 16-32 | 8-16 |
| 5,000 | 150,000 | 32-64 | 16-32 |

Follows standard Kubernetes limits for max nodes/pods (see [Kubernetes large cluster guidance](https://kubernetes.io/docs/setup/best-practices/cluster-large/)).

### Storage Requirements

| Role | Usage (k0s part) | Minimum Required |
|------|-------------------|------------------|
| Controller node | ~0.5 GB | ~0.5 GB |
| Worker node | ~1.3 GB | ~1.6 GB |
| Controller + worker | ~1.7 GB | ~2.0 GB |

- **SSD recommended** for etcd (cluster latency/throughput sensitive to storage)
- Worker nodes need **at least 15% free disk space**

### Measured Controller Memory Consumption (k0s v1.22.4+k0s.2)

| Workers | Pods (besides default) | Memory (MB) |
|---------|------------------------|-------------|
| 1 | 0 | 510 |
| 1 | 100 | 600 |
| 20 | 0 | 660 |
| 20 | 2,000 | 1,000 |
| 50 | 0 | 790 |
| 50 | 5,000 | 1,400 |
| 100 | 0 | 1,000 |
| 100 | 10,000 | 2,300 |
| 200 | 0 | 1,500 |
| 200 | 20,000 | 3,300 |

Measurement environment: Ubuntu 20.04.3 LTS (OS ~180 MB), AWS t3.xlarge (4 vCPUs, 16 GB RAM), nginx:1.21.4 pod image.

### Supported Architectures
- `x86_64`
- `aarch64`
- `armv7l`
- `riscv64` (No pre-compiled binaries, no CI coverage)

### Supported Operating Systems (CI-tested)

| OS | Versions |
|----|----------|
| Amazon Linux | 2023 |
| Alpine Linux | 3.21, 3.23 |
| CentOS Stream | 9, 10 (Coughlan) |
| Debian GNU/Linux | 11 (bullseye), 12 (bookworm) |
| Fedora CoreOS | stable stream |
| Fedora Linux | 41 (Cloud Edition) |
| Flatcar Container Linux | by Kinvolk |
| RHEL | 7.9 (Maipo), 8.10 (Ootpa), 9.7 (Plow) |
| Rocky Linux | 8.10 (Green Obsidian), 9.5 (Blue Onyx) |
| SUSE Linux Enterprise Server | 15 SP6 |
| Ubuntu | 20.04 LTS, 22.04 LTS, 24.04 |

Also runs on **Windows** (Server 2019, 2022 - experimental).

---

## 3. Networking (CNI)

### In-Cluster Networking
- Supports any standard CNI network provider
- Two built-in providers: **Kube-router** (default) and **Calico**
- Custom CNI: set `provider: custom` in `spec.network` - deploy your own CNI manually

### Kube-router (Default)
- Built into k0s, uses standard Linux networking stack
- CNI networking **without overlays** using BGP
- ~15% less resource usage than Calico
- Does **NOT** support Windows nodes
- Config options: `autoMTU` (default: true), `mtu`, `metricsPort` (default: 8080), `hairpin` (Enabled/Allowed/Disabled), `ipMasq` (default: false), `peerRouterIPs` (DEPRECATED), `peerRouterASNs` (DEPRECATED), `extraArgs`, `rawArgs`

### Calico
- Layer 3 container networking, routes packets to pods
- Supports pod-specific network policies
- Default mode: **VXLAN** (also supports IP in IP via `bird` mode)
- Uses more resources than Kube-router
- **Supports Windows nodes**
- Config options:
  - `mode`: `bird` or `vxlan` (default), deprecated `ipip`
  - `overlay`: `Always` (default), `CrossSubnet`, `Never` (requires `mode=vxlan`)
  - `vxlanPort`: default 4789
  - `vxlanVNI`: default 4096
  - `mtu`: default 0 (auto-detect)
  - `wireguard`: default false (requires host WireGuard ready)
  - `flexVolumeDriverPath`: default `/usr/libexec/k0s/kubelet-plugins/volume/exec/nodeagent~uds`
  - `ipAutodetectionMethod`: default `""`
  - `envVars`: map of environment variables
- Pre-defined env vars: `CALICO_IPV4POOL_CIDR`, `CALICO_DISABLE_FILE_LOGGING=true`, `FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT`, `FELIX_LOGSEVERITYSCREEN=info`, `FELIX_HEALTHENABLED=true`, `FELIX_PROMETHEUSMETRICSENABLED=true`, `FELIX_FEATUREDETECTOVERRIDE=ChecksumOffloadBroken=true`

### Controller-Worker Communication
- Uses **Konnectivity service** to proxy traffic from API server to workers
- Enables isolated control plane while maintaining Kubernetes API functionality
- Workers need outbound access port **8132** (Konnectivity) and port **6443** (Kube-API)

### Required Ports and Protocols

| Protocol | Port | Service | Direction | Notes |
|----------|------|---------|-----------|-------|
| TCP | 2380 | etcd | controller ↔ controller | |
| TCP | 6443 | kube-apiserver | worker, CLI → controller | mTLS, ServiceAccount tokens with RBAC |
| TCP | 179 | kube-router | worker ↔ worker | BGP routing sessions |
| UDP | 4789 | calico | worker ↔ worker | Calico VXLAN overlay |
| TCP | 10250 | kubelet | controller, worker → host * | mTLS authenticated kubelet API |
| TCP | 9443 | k0s api | controller ↔ controller | k0s controller join API, TLS with token auth |
| TCP | 8132 | konnectivity | worker ↔ controller | Reverse tunnel between kube-apiserver and worker kubelets |
| TCP | 112 | keepalived | controller ↔ controller | Only for control plane LB VRRPInstances (unless unicast enabled); also uses port 122 on multicast IP 224.0.0.18 (RFC 3768) |

Must also enable all traffic to/from **podCIDR** and **serviceCIDR** subnets on worker nodes.

### iptables Modes
- k0s auto-detects `legacy` vs `nftables`, **prefers nftables**
- Check mode: `ls -lah /var/lib/k0s/bin/` (symlink target reveals mode)
- k0s ships its own iptables version in `/var/lib/k0s/bin/` tested with all bundled K8s components
- Host iptables version incompatibility can cause networking issues

### Firewalld
- Must run with same backend (`nftables` or `iptables`) as k0s/Kubernetes components
- Configure via `FirewallBackend` in `/etc/firewalld/firewalld.conf`
- Firewalld enabled by default in **Oracle Linux**
- XML service definitions provided for controller (`k0s-controller.xml`) and worker (`k0s-worker.xml`)
- Worker nodes also need `--add-masquerade` and source rules for pod/service CIDRs

---

## 4. Configuration Options

### Config File
- Default config generated by: `k0s config create > /etc/k0s/k0s.yaml`
- Supports **partial configurations** (defaults used for missing values)
- API version: `k0s.k0sproject.io/v1beta1`, kind: `ClusterConfig`
- Config path default: `/etc/k0s/k0s.yaml`
- Apply changes: `sudo k0s stop && sudo k0s start`

### `spec.api` Options
| Field | Default | Description |
|-------|---------|-------------|
| `address` | first non-local address | IP for cluster components to talk to API server |
| `onlyBindToAddress` | false | Bind API server only to configured address |
| `externalAddress` | - | Load balancer address for HA |
| `sans` | - | Additional SANs for API server certificate |
| `ca.expiresAfter` | 87600h (10 years) | CA cert expiration |
| `ca.certificatesExpireAfter` | 8760h (1 year) | Server cert expiration |
| `extraArgs` | empty | Extra args for kube-apiserver (preferred over rawArgs) |
| `rawArgs` | empty | Raw args appended after extraArgs |
| `port` | 6443 | Kubernetes API server port |
| `k0sApiPort` | 9443 | k0s API server port |

### `spec.storage` Options
| Field | Default | Description |
|-------|---------|-------------|
| `type` | `etcd` | Data store type: `etcd` or `kine` |
| `etcd.peerAddress` | auto | Node address for etcd peering |
| `etcd.extraArgs` | empty | Extra args for etcd |
| `etcd.rawArgs` | empty | Raw args for etcd |
| `etcd.ca.expiresAfter` | 87600h | etcd CA cert expiration |
| `etcd.ca.certificatesExpireAfter` | 8760h | etcd server cert expiration |
| `etcd.externalCluster` | - | External etcd config (endpoints, etcdPrefix, caFile, clientCertFile, clientKeyFile) |
| `kine.dataSource` | - | kine data source URL |
| `kine.extraArgs` | empty | Extra args for kine |
| `kine.rawArgs` | empty | Raw args for kine |

### `spec.network` Options
| Field | Default | Description |
|-------|---------|-------------|
| `provider` | `kuberouter` | `calico`, `kuberouter`, or `custom` |
| `podCIDR` | `10.244.0.0/16` | Pod network CIDR |
| `serviceCIDR` | `10.96.0.0/12` | Service VIP CIDR |
| `primaryAddressFamily` | auto (IPv4) | Primary family: empty, `IPv4`, `IPv6` |
| `clusterDomain` | `cluster.local` | Cluster domain |
| `dualStack.enabled` | false | IPv4/IPv6 dual-stack |

### `spec.network.kubeProxy` Options
| Field | Default | Description |
|-------|---------|-------------|
| `disabled` | false | Disable kube-proxy entirely |
| `mode` | `iptables` | `iptables`, `ipvs`, `nftables`, `userspace` |
| `healthzBindAddress` | `0.0.0.0:10256` | Health check bind address |
| `metricsBindAddress` | `0.0.0.0:10249` | Metrics bind address |
| `extraArgs` | empty | Extra args for kube-proxy |
| `rawArgs` | empty | Raw args for kube-proxy |

### `spec.network.nodeLocalLoadBalancing` Options
| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | false | Enable node-local LB for API server access from workers |
| `type` | `EnvoyProxy` | `EnvoyProxy` or `Traefik` |
| `envoyProxy.apiServerBindPort` | 7443 | Envoy LB port for API server |
| `envoyProxy.konnectivityServerBindPort` | 7132 | Envoy LB port for konnectivity |
| `traefik.apiServerBindPort` | 7443 | Traefik LB port for API server |
| `traefik.konnectivityServerBindPort` | 7132 | Traefik LB port for konnectivity |

Note: EnvoyProxy NLLB not supported on ARMv7, RISC-V, and Windows.

### `spec.network.controlPlaneLoadBalancing` Options
| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | false | Enable control plane LB |
| `type` | - | Currently only `Keepalived` |
| `keepalived.userSpaceProxyBindPort` | 6444 | Internal user space proxy port |
| `keepalived.disableLoadBalancer` | false | Disable the LB |
| `keepalived.configTemplateVRRP` | empty | Custom Keepalived VRRP template |
| `keepalived.configTemplateVS` | empty | Custom Keepalived VS template |

#### VRRP Instance Options
- `virtualIPs`: List of CIDR virtual IPs
- `interface`: NIC (device name or MAC address, or auto-detect from default route)
- `virtualRouterID`: 1-255 (auto-numbered from 51 if not set, all controllers must match)
- `advertIntervalSeconds`: default 1
- `authPass`: 1-8 characters (not security, prevents accidental misconfig)
- `unicastPeers`: list of IPs for unicast (requires `unicastSourceIP`)
- `addressLabel`: for IPv6 VIPs, RFC 6724 routing preference, default 10000

#### Virtual Server Options
- `ipAddress`: listen address
- `delayLoop`: default 1m (microsecond precision)
- `lbAlgo`: `rr` (default), `wrr`, `lc`, `wlc`, `lblc`, `dh`, `sh`, `sed`, `nq`
- `lbKind`: `DR` (default), `NAT`, `TUN`
- `persistenceTimeoutSeconds`: 1-2678400, default 360

### Other Config Sections
| Section | Key Options |
|---------|-------------|
| `spec.controllerManager` | `extraArgs`, `rawArgs` |
| `spec.scheduler` | `extraArgs`, `rawArgs` |
| `spec.workerProfiles` | Array of `{name, values}` for kubelet config overrides (cannot override: `clusterDNS`, `clusterDomain`, `apiVersion`, `kind`, `staticPodURL`) |
| `spec.featureGates` | Array of `{name, enabled, components}` - components: `kube-apiserver`, `kube-controller-manager`, `kubelet`, `kube-scheduler`, `kube-proxy` |
| `spec.images` | `repository` (global prefix), `default_pull_policy`, per-component image overrides |
| `spec.extensions.helm` | `concurrencyLevel` (default: 5), repositories, charts |
| `spec.konnectivity` | `agentPort` (default: 8132), `adminPort` (default: 8133) |
| `spec.telemetry` | `enabled` (default: true), 10-minute interval |

### Component Patches (Experimental)
Patchable components: `coreDNS`, `kube-proxy`, `kube-router`, `Calico`, `metrics-server`
- Patch types: `JSON` (RFC 6902), `MergePatch` (RFC 7386), `StrategicMergePatch`
- Configured via `{target: {kind, name, namespace?}, patch: {type, content}}`

### Disabling Controller Components
Flag: `--disable-components`
Valid items: `applier-manager`, `autopilot`, `control-api`, `coredns`, `csr-approver`, `endpoint-reconciler`, `helm`, `konnectivity-server`, `kube-controller-manager`, `kube-proxy`, `kube-scheduler`, `metrics-server`, `network-provider`, `node-role`, `system-rbac`, `update-prober`, `windows-node`
Only always-on component: Kubernetes API server.

### Kubelet Root Directory
- Default: `/var/lib/k0s/kubelet` (inside `--data-dir` which defaults to `/var/lib/k0s/`)
- Change with `--kubelet-root-dir` flag (e.g., `--kubelet-root-dir=/var/lib/kubelet`)
- Changing on existing node won't remove old directories
- CSI plugins may mount this directory - inconsistent values across nodes causes problems

---

## 5. Autopilot (Auto-Updates)

### Overview
- Creates `Plan` YAMLs defining update payloads and target nodes
- Public update server: `https://updates.k0sproject.io/`
- Single channel: `edge_release` (latest released version)
- API version: `autopilot.k0sproject.io/v1beta2`

### How It Works
1. Create a `Plan` YAML with update payload and target definitions
2. Apply with `kubectl apply`
3. Monitor progress via `.status` of the Plan

### Safeguards
1. **Stateless Component**: Controllers can disappear, backups resume operations
2. **Workers Update After Controllers**: All controllers update first; workers only after all controllers succeed
3. **Plans are Immutable**: After evaluation, no changes to plan recognized (except status)
4. **Controller Quorum Safety**: Queries all controllers for `/ready` before scheduling update
5. **Controllers Update Sequentially**: Fixed to 1 concurrent controller update always
6. **Update Payload Verification**: Optional SHA256 hash verification of downloaded binaries

### Plan Commands

#### `k0supdate` Command
| Field | Required | Description |
|-------|----------|-------------|
| `version` | yes | Target version |
| `platforms.*.url` | yes | Download URL (format: `$GOOS-$GOARCH`, e.g., `linux-amd64`) |
| `platforms.*.sha256` | no | SHA256 hash for verification |
| `targets.controllers.limits.concurrent` | fixed=1 | Always 1 for controllers |
| `targets.workers.limits.concurrent` | default=1 | Number of concurrent worker updates |
| `targets.*.discovery.static.nodes[]` | for static | List of hostnames |
| `targets.*.discovery.selector.labels` | optional | Label selectors (logical AND with fields) |
| `targets.*.discovery.selector.fields` | optional | Field selectors (only `metadata.name` available) |
| `forceupdate` | optional | Force update |

#### `airgapupdate` Command
| Field | Required | Description |
|-------|----------|-------------|
| `version` | yes | Airgap bundle version |
| `platforms.*.url` | yes | Download URL |
| `platforms.*.sha256` | no | SHA256 hash |
| `workers.limits.concurrent` | default=1 | Concurrent worker updates |

### Automatic Updates (UpdateConfig)
| Field | Default | Description |
|-------|---------|-------------|
| `spec.channel` | `stable` | `stable` or `unstable` |
| `spec.updateServer` | `https://updates.k0sproject.io` | Update server URL |
| `spec.upgradeStrategy.type` | - | `cron` (DEPRECATED) or `periodic` |
| `spec.upgradeStrategy.periodic.days` | - | Weekdays for updates |
| `spec.upgradeStrategy.periodic.startTime` | - | Start time (HH:MM) |
| `spec.upgradeStrategy.periodic.length` | - | Window length (e.g., `2h`) |
| `spec.planSpec` | - | Plan spec for auto-generated Plan |

### Plan Status States
| State | Description | Ends Plan? |
|-------|-------------|-----------|
| `IncompleteTargets` | Nodes don't have associated Node/ControlNode objects | Yes |
| `Schedulable` | Plan can be re-evaluated | No |
| `SchedulableWait` | Scheduling in progress | No |
| `Completed` | Plan ran successfully | Yes |
| `Restricted` | Node types violate `--exclude-from-plans` restrictions | Yes |

### Node Status States
| State | Description |
|-------|-------------|
| `SignalPending` | Node awaiting update signal |
| `SignalSent` | Update signal applied successfully |
| `SignalMissingPlatform` | No update provided for this platform |
| `SignalMissingNode` | No associated Node/ControlNode object |

---

## 6. Manifest Deployer

- Runs on controller nodes
- Watches `/var/lib/k0s/manifests/` for `.yaml` files (NOT `.yml`)
- Each direct descendant directory is its own "stack"
- Nested subdirectories are **NOT** auto-deployed
- Works like `kubectl apply` but continuously monitors for changes
- On file removal, **automatically prunes** associated resources
- **Explicitly define namespace** in manifests (no default namespace)
- k0s uses its own internal stack mechanism - don't touch k0s-managed manifests

---

## 7. Helm Charts Integration

### Two Methods
1. **Chart Custom Resources** (recommended): `Chart` CRDs in `kube-system` namespace
2. **k0s Configuration** (alternative): `spec.extensions.helm` in k0s.yaml

### Chart CRD (Recommended)
- API version: `helm.k0sproject.io/v1beta1`, kind: `Chart`
- Must be created in `kube-system` namespace (security requirement)
- Can deploy to any target namespace
- No k0s restart needed
- Supports: traditional repos, OCI registries (public/authenticated/mTLS), local chart files, secret-based auth

### Chart CRD Spec Fields
| Field | Default | Description |
|-------|---------|-------------|
| `chartName` | required | `repo/chart`, `oci://registry/chart`, or `/path/to/chart.tgz` |
| `version` | required | Chart version |
| `namespace` | required | Target namespace |
| `releaseName` | - | Defaults to Chart resource name |
| `values` | - | Custom values as YAML string |
| `timeout` | `10m` | Release install timeout |
| `forceUpgrade` | `true` | Use `--force` on upgrade |
| `repository.url` | - | Repository URL |
| `repository.username` | - | Basic auth username |
| `repository.password` | - | Basic auth password |
| `repository.caFile` | - | CA bundle for HTTPS |
| `repository.certFile` | - | TLS cert for mTLS |
| `repository.keyFile` | - | TLS key for mTLS |
| `repository.insecure` | false | Skip TLS verification |
| `repository.configFrom.secretRef.name` | - | Secret reference for credentials |

### Chart Lifecycle
- **Install**: When Chart resource created
- **Upgrade**: When spec changes (version, values)
- **Uninstall**: When Chart resource deleted

### k0s.yaml Helm Config
| Field | Default | Description |
|-------|---------|-------------|
| `concurrencyLevel` | 5 | Helm concurrency |
| `repositories[].name` | required | Repository name |
| `repositories[].url` | required | Repository URL |
| `repositories[].insecure` | true | Skip TLS checks |
| `charts[].name` | - | Release name |
| `charts[].chartname` | - | `repository/chartname` or path to tgz |
| `charts[].version` | - | Chart version |
| `charts[].timeout` | - | Install timeout |
| `charts[].values` | - | Custom values YAML |
| `charts[].namespace` | - | Target namespace |
| `charts[].forceUpgrade` | true | Use `--force` on upgrade |
| `charts[].order` | 0 | Apply order |

Default Helm options: `--create-namespace`, `--atomic`, `--force` (upgrade only), `--wait`, `--wait-for-jobs`

Only classic Helm repos with valid `index.yaml` supported. Direct links to chart folders/files won't work.

---

## 8. Air-Gap Installation

### Image Bundles
- k0s uses **OCI archives** (tarball of OCI Image Layout)
- Watches `<data-dir>/images` folder for bundles, auto-imports to container runtime
- Pre-built bundles available per-platform on GitHub releases

### Creating Image Bundles

#### k0s Built-in Tooling
```bash
k0s airgap list-images --all > airgap-images.txt
k0s airgap bundle-artifacts -v -o image-bundle.tar < airgap-images.txt
```

#### From Running Worker
```bash
k0s ctr images export image-bundle.tar $(k0s airgap list-images | xargs)
```

#### Docker
```bash
xargs -I{} docker pull {} < airgap-images.txt
docker image save -o image-bundle.tar $(xargs < airgap-images.txt)
```

### Placing Bundles
- Copy `image-bundle.tar` to `/var/lib/k0s/images/` on **worker nodes only**
- Controllers don't use image bundles

### k0sctl Upload
```yaml
files:
  - src: /path/to/airgap-bundle-amd64.tar
    dstDir: /var/lib/k0s/images
    perm: 0755
```

### Disable Image Pulling
```yaml
spec:
  images:
    default_pull_policy: Never
```

### Platform Matching
k0s uses "loose" platform matching - on arm/v8, also imports arm/v7, arm/v6, arm/v5 images.

---

## 9. Storage (CSI)

- Supports all Kubernetes storage solutions via **Container Storage Interface (CSI)**
- Kubelet root dir default: `/var/lib/k0s/kubelet` (different from vanilla `/var/lib/kubelet`)
- Consult CSI driver docs for customizing kubelet path if needed

### Popular Storage Solutions
- Rook-Ceph (Open Source)
- GlusterFS (Open Source)
- Longhorn (Open Source)
- OpenEBS (Open Source)
- Amazon EBS
- Google Persistent Disk
- Azure Disk
- Portworx

---

## 10. CIS Benchmark Support

### Running Kube-bench
```bash
kube-bench run --config-dir docs/kube-bench/cfg/ --benchmark k0s-1.0
```

### Disabled Checks Summary

#### Master Node (8 checks disabled)
| ID | Reason |
|----|--------|
| 1.2.10 | EventRateLimit requires external yaml config |
| 1.2.12 | AlwaysPullImages not passed for air-gap functionality |
| 1.2.22 | Audit log path - left for user to configure |
| 1.2.23 | Audit log maxage - left for user to configure |
| 1.2.24 | Audit log maxbackup - left for user to configure |
| 1.2.25 | Audit log maxsize - left for user to configure |
| 1.2.33 | Encryption provider config not enabled by default |
| 1.2.34 | Encryption providers not enabled by default |

#### Worker Node (4 checks disabled)
| ID | Reason |
|----|--------|
| 4.1.1 | k0s doesn't use kubelet service file |
| 4.1.2 | k0s doesn't use kubelet service file |
| 4.2.6 | `--protect-kernel-defaults` not set (K8s issue #66693) |
| 4.2.10 | TLS certs auto-rotated by k0s |

#### Control Plane (3 checks disabled)
| ID | Reason |
|----|--------|
| 3.1.1 | Client certificate auth skipped for automation |
| 3.2.1 | No default audit policy (users can add via `spec.api.extraArgs`) |
| 3.2.2 | Same as above |

#### Kubernetes Policies
All policy checks disabled (manual, user decides).

---

## 11. High Availability (HA)

### Architecture
- Distribute control plane across multiple nodes + load balancer on top
- etcd co-located with controller nodes (default)
- **2-node control plane considered HA** (though not HA from etcd perspective)
- For etcd HA: **3 or 5 controller nodes recommended**

### Network Considerations
- Plan to allocate controllers into **different zones**
- Avoids single-zone failures

### Load Balancer Requirements
TCP load balancer routing to all controllers on:
- **6443** (Kubernetes API)
- **8132** (Konnectivity)
- **9443** (controller join API)

### HAProxy Example Config
```
frontend kubeAPI
    bind :6443
    mode tcp
    default_backend kubeAPI_backend
frontend konnectivity
    bind :8132
    mode tcp
    default_backend konnectivity_backend
frontend controllerJoinAPI
    bind :9443
    mode tcp
    default_backend controllerJoinAPI_backend
```

### Shared CA Certificates
All controllers must share:
```
/var/lib/k0s/pki/ca.key
/var/lib/k0s/pki/ca.crt
/var/lib/k0s/pki/sa.key
/var/lib/k0s/pki/sa.pub
/var/lib/k0s/pki/etcd/ca.key
/var/lib/k0s/pki/etcd/ca.crt
```

### Configuration
```yaml
spec:
  api:
    externalAddress: <load balancer public ip address>
```

---

## 12. Upgrade & Lifecycle Management

### Upgrade Process
k0s upgrade = replace single binary + restart service

### Local Upgrade
```bash
sudo k0s stop
curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sudo sh
sudo k0s start
```

### k0sctl Cluster Upgrade
```yaml
spec:
  k0s:
    version: v1.36.3+k0s.2
```
```bash
k0sctl apply
```

### k0sctl Upgrade Process
1. Upgrade each controller **one at a time** (no downtime with multiple controllers)
2. Upgrade workers in **batches of 10%**
3. Drain workers before upgrade (skip with `--no-drain`)
4. Continues once upgraded nodes return to **Ready** state

### Backup/Restore
- `k0s backup` - back up k0s configuration
- `k0s restore` - restore from backup archive (use `-` for stdin)

---

## 13. CLI Reference

### k0s Commands
| Command | Description |
|---------|-------------|
| `k0s airgap` | Tooling for airgapped installations |
| `k0s api` | Run the controller API |
| `k0s backup` | Back up k0s configuration (must be root/sudo) |
| `k0s completion` | Generate completion script |
| `k0s config` | Configuration related sub-commands |
| `k0s controller` | Run controller |
| `k0s ctr` | containerd CLI |
| `k0s docs` | Generate k0s command documentation |
| `k0s etcd` | Manage etcd cluster |
| `k0s install` | Install k0s on new system (must be root/sudo) |
| `k0s keepalived-config` | Keepalived configuration sub-commands |
| `k0s kubeconfig` | Create kubeconfig for specified user |
| `k0s kubectl` | kubectl controls Kubernetes cluster manager |
| `k0s reset` | Uninstall k0s (must be elevated privileges) |
| `k0s restore` | Restore k0s state from backup (must be root/sudo) |
| `k0s start` | Start k0s service (must be root/sudo) |
| `k0s status` | Get k0s instance status |
| `k0s stop` | Stop k0s service (must be root/sudo) |
| `k0s sysinfo` | Display system information |
| `k0s token` | Manage join tokens |
| `k0s version` | Print k0s version |
| `k0s worker` | Run worker |

### k0sctl Tool
- Single binary for bootstrapping/managing k0s clusters
- Connects via SSH, gathers host info, forms cluster
- Recommended for production installations
- Required for automatic upgrades

#### k0sctl Commands
- `k0sctl init` - generate k0sctl.yaml
- `k0sctl apply` - deploy/upgrade cluster
- `k0sctl kubeconfig` - generate kubeconfig

#### Known Limitations
- No host discovery - only operates on listed hosts
- Can only **add** nodes, **cannot remove** existing nodes

---

## 14. User Management & RBAC

### Key Points
- Kubernetes/k0s has **no built-in user management**
- Relies solely on external sources for user authentication
- Client certificates considered external source (K8s validates trusted CA)

### Client Certificate Caveats
- Valid for **one year** (long expiration)
- **Cannot be revoked** (general Kubernetes limitation)

### Adding Users
```bash
k0s kubeconfig create [username]
```

### Granting Cluster Access
```bash
# Create kubeconfig with system:masters group
k0s kubeconfig create --groups "system:masters" testUser > k0s.config

# Create role binding
k0s kubectl create clusterrolebinding --kubeconfig k0s.config \
  testUser-admin-binding --clusterrole=admin --user=testUser
```

### Recommended: OpenID Connect
Use external Identity Provider via OIDC for production.

---

## 15. Monitoring / Observability

### System Components Monitoring (Opt-in)
```bash
sudo k0s install controller --enable-metrics-scraper
```

#### Creates in `k0s-system` namespace
- `k0s-pushgateway` pod (Deployment + Service on port 9091)
- Pushgateway with TTL (default: 2 minutes)

#### Scraped Components
- kube-scheduler
- kube-controller-manager
- etcd
- kine
- (kube-apiserver NOT scraped - accessible via `kubernetes` endpoint)

#### ServiceMonitor for Prometheus Operator
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: k0s
  namespace: k0s-system
spec:
  endpoints:
  - port: http
    honorLabels: true
  selector:
    matchLabels:
      app: k0s-observability
      component: pushgateway
      k0s.k0sproject.io/stack: metrics
```

#### Telemetry
- Enabled by default (`spec.telemetry.enabled: true`)
- 10-minute collection interval
- Sends to k0s development team
- Disable: `spec.telemetry.enabled: false`

---

## 16. Windows Worker Support (Experimental)

### Status
**EXPERIMENTAL** - under active development

### Prerequisites
- At least one Linux worker and one Linux control plane required
- Supported: **Windows Server 2019** and **Windows Server 2022**

### Installation Steps
1. Generate worker token: `k0s token create --role=worker > worker-token.txt`
2. Transfer token to Windows at `C:\k0s-token.txt`
3. Enable Containers feature: `Install-WindowsFeature -Name Containers` (reboot required)
4. Download k0s binary to `$env:LOCALAPPDATA\Microsoft\WindowsApps\k0s.exe`
5. Install and start: `k0s install worker --token-file $TOKEN_FILE && k0s start`

### Key Notes
- k0s supervises `kubelet.exe` and `kube-proxy.exe`
- For AWS: Disable "Change Source/Dest. Check" on EC2 network interface
- Requires Calico CNI (Kube-router does NOT support Windows)

---

## 17. Extensions Examples

### MetalLB Load Balancer
- Implements Kubernetes LoadBalancer service type
- Typical use: bare-metal deployments (no cloud provider dependencies)
- Compatible with default Kube-Router CNI (except BGP mode)
- For IPVS mode: enable strict ARP (`spec.network.kubeProxy.ipvs.strictARP: true`)
- Port **7946** (TCP & UDP) must be allowed between nodes
- No other software on port 7946 (e.g., docker daemon)

### Other Documented Extensions
- NGINX Ingress Controller
- Traefik Ingress Controller
- Ceph Storage with Rook
- GitOps with Flux
- OpenEBS storage
- Longhorn storage

---

## 18. Security Features

### Signed Binaries
- k0s binaries are signed (verification available)

### Pod Security Standards
- Support documented (see `/podsecurity/`)

### SELinux
- Support documented (see `/selinux/`)

### Certificate Management
- Custom CA certificates supported
- CA cert: default 87600h (10 years) expiry
- Server cert: default 87600h expiry (configurable via `ca.expiresAfter` and `ca.certificatesExpireAfter`)

### Cloud Providers
- Supported for load balancer and storage configuration

---

## 19. Known Issues & Caveats

1. **k0s cannot shrink etcd cluster** - must manually remove node before shutdown
2. **Changing network provider requires full cluster redeployment**
3. **k0sctl cannot remove nodes** - only add
4. **Client certificates cannot be revoked** (Kubernetes limitation)
5. **Calico overlay must be disabled** via `mode=vxlan` + `overlay=Never`
6. **iptables version conflicts** between k0s-bundled and host versions can cause networking issues
7. **Firewalld backend mismatch** (nftables vs iptables) causes networking failure
8. **nftables kube-proxy** requires container nftables version <= host OS version (else segfault)
9. **CSI plugins** may need kubelet root dir path customization
10. **ControlNode CRD instances** not auto-removed when controllers disappear - operator responsibility
11. **Worker version skew** - workers must not be newer than API server (upgrade controllers first)

---

## 20. Directories

Default data directory: `/var/lib/k0s/`
- `/var/lib/k0s/pki/` - PKI certificates
- `/var/lib/k0s/manifests/` - Manifest deployer directory
- `/var/lib/k0s/images/` - Air-gap image bundles
- `/var/lib/k0s/bin/` - Bundled binaries (iptables, etc.)
- `/var/lib/k0s/kubelet/` - Kubelet root directory (default)
- `/etc/k0s/` - Configuration directory

---

## 21. Community & Governance

- **License**: Apache License 2.0 (code), CC-BY-SA-4.0 (docs)
- **Community**: Kubernetes Slack `#k0s` channel
- **Blog**: https://blog.k0sproject.io/
- **GitHub**: https://github.com/k0sproject/k0s
- **X/Twitter**: https://x.com/k0sproject
- **CNCF**: Under LF Projects, LLC
  - Kubernetes AI conformance
  - General Technical Review
  - TAG-Security self-assessment
- **Version Skew Policy**: Follows Kubernetes version skew policy
