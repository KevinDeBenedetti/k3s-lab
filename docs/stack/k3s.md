# k3s — Lightweight Kubernetes

[k3s](https://k3s.io) is a certified, production-ready Kubernetes distribution packaged as a single binary (~100 MB). It is optimized for small machines: homelabs, edge and IoT.

## Why k3s

| Feature              | Value                         |
| -------------------- | ----------------------------- |
| Single binary        | No Docker daemon required     |
| Built-in containerd  | Reduced resource footprint    |
| ARM + x86 support    | Pi, mini PC, VM or VPS        |
| Certified Kubernetes | 100% API compatible           |
| Automatic TLS        | Internal cluster PKI included |

---

## Architecture

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│         Server (node 1)         │    │         Agent (node 2)          │
│                                 │    │                                 │
│  k3s server                     │    │  k3s agent                      │
│  ├─ kube-apiserver  :6443       │◄───│  ├─ kubelet                     │
│  ├─ etcd (embedded)             │    │  ├─ kube-proxy                  │
│  ├─ controller-manager          │    │  └─ containerd                  │
│  └─ scheduler                   │    │                                 │
│                                 │    │  Flannel VXLAN  :8472/udp       │
│  Traefik (ingress)  :80/:443    │    │  Kubelet API    :10250/tcp      │
│  cert-manager                   │    │                                 │
└─────────────────────────────────┘    └─────────────────────────────────┘
           │                                         │
           └─────────── Flannel VXLAN ───────────────┘
                        (pod overlay network)
```

---

## Prerequisites

| Requirement                      | Notes                              |
| -------------------------------- | ---------------------------------- |
| Ubuntu 22.04+ / Debian 12+       | Both nodes                         |
| 2 vCPU / 2 GB RAM (server)       | 1 GB minimum for agent             |
| Reachable IP on each node        | Required for TLS SAN + UFW rules   |
| SSH access as root or sudo user  | Bootstrap uses `INITIAL_USER=root` |
| Port `6443` open on server       | k3s API server                     |
| Ports `80`, `443` open on server | HTTP + HTTPS traffic               |

---

## Install flags explained

The `k3s_server` role composes the installer's arguments (`INSTALL_K3S_EXEC`)
from its variables. With the defaults it runs:

```bash
INSTALL_K3S_VERSION="<k3s_version>" bash /tmp/k3s-install.sh   # get.k3s.io, checksum-pinned
# INSTALL_K3S_EXEC:
server
  --node-ip <k3s_node_ip>
  --cluster-cidr 10.42.0.0/16 --service-cidr 10.43.0.0/16 --cluster-dns 10.43.0.10
  --flannel-backend vxlan                    # UDP 8472
  --disable traefik --disable servicelb      # Traefik is installed by Helm
  --kube-apiserver-arg=audit-policy-file=…   # files/audit-policy.yaml
  --secrets-encryption=true                  # never remove once initialised
  --kube-apiserver-arg=audit-log-path=/var/log/k3s-audit.log …
  --protect-kernel-defaults
```

Optional flags appear only when their variable is set: `--advertise-address`,
`--node-external-ip`, `--flannel-iface`, `--node-label`, `--node-taint`.
Extra API server certificate SANs (`k3s_tls_sans`) go in a
`config.yaml.d` drop-in instead. See
[Configuration → Ansible role variables](../configuration.md).

### Changing an argument on an installed node

The roles compare the arguments the `k3s` (or `k3s-agent`) unit runs with the
ones they would install, ignoring order. When they differ, the playbook prints
the difference and re-runs the installer at the same version, which rewrites
the unit and restarts k3s once. Before this check existed, a changed argument
only reached a node with the next version bump.

> Upgrading from k3s-lab 0.24 or earlier: the first run adds
> `--audit-policy-file` to the server, so it reinstalls k3s at the same version
> and restarts it once. Agents with unchanged arguments are not touched.

Files k3s reads only at start-up (the audit policy, the kubelet drop-in, the
TLS SAN list) are written before the installer. When one changes and the
installer does not run, the role restarts k3s itself, once.

### Audit log

`audit-log-*` flags alone record nothing: the API server logs only what a
policy selects. The role installs a generic baseline
(`roles/k3s_server/files/audit-policy.yaml`): health probes, leases, events and
node heartbeats are dropped, Secrets and ConfigMaps are logged at `Metadata`
only (never their content), and writes to RBAC and admission configuration keep
their request body. Use your own with `k3s_audit_policy_src`, or turn it off
with `k3s_audit_policy_enabled: false`.

---

## Sysctl requirements

k3s requires specific kernel parameters. These are written to `/etc/sysctl.d/99-z-k3s.conf`:

```ini
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
vm.panic_on_oom                     = 0
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
```

> The `99-z-` prefix ensures these values are applied **after** any hardening configs (e.g. `99-security.conf`), so `ip_forward=1` is the final value.

---

## Firewall rules (UFW)

### Server node

| Port                  | Protocol | Purpose                                 |
| --------------------- | -------- | --------------------------------------- |
| `80`                  | TCP      | HTTP (Traefik + ACME HTTP-01 challenge) |
| `443`                 | TCP      | HTTPS (Traefik TLS termination)         |
| `6443`                | TCP      | Kubernetes API server                   |
| `10.42.0.0/16`        | any      | k3s pod CIDR (Flannel)                  |
| `10.43.0.0/16`        | any      | k3s service CIDR                        |
| `8472` from AGENT_IP  | UDP      | Flannel VXLAN tunnel                    |
| `10250` from AGENT_IP | TCP      | kubelet API                             |

### Agent node

| Port                   | Protocol | Purpose              |
| ---------------------- | -------- | -------------------- |
| `8472` from SERVER_IP  | UDP      | Flannel VXLAN tunnel |
| `10250` from SERVER_IP | TCP      | kubelet API          |

---

## Installation workflow

### 1. Bootstrap server

```bash
task provision:server
```

This runs the Ansible `k3s-server.yml` playbook which:
1. Applies common setup (packages, kernel modules, sysctl, UFW)
2. Installs k3s server with configured flags
3. Waits for the node to be `Ready`
4. Reads the node token (used to join agents)
5. Fetches kubeconfig with public IP replaced
6. Optionally sets up WireGuard VPN

### 2. Bootstrap agent

```bash
task provision:agents
```

This runs the Ansible `k3s-agent.yml` playbook which:
1. Applies common setup on agent nodes
2. Installs k3s agent with server URL and node token
3. Configures UFW for cluster communication

### 3. Fetch kubeconfig

```bash
task kubeconfig:fetch
```

Fetches `/etc/rancher/k3s/k3s.yaml` from the server, replaces `127.0.0.1` with the public IP, and merges it into `~/.kube/config` under the context name `KUBECONFIG_CONTEXT`.

---

## Uninstall

```bash
task provision:reset       # Uninstall k3s from all nodes (DESTRUCTIVE)
```

The Ansible `reset.yml` playbook:
- Runs the official `k3s-uninstall.sh` or `k3s-agent-uninstall.sh`
- Cleans up CNI interfaces (`flannel.1`, `cni0`)
- Flushes iptables rules
- Unmounts k3s bind mounts

---

## Node token

The node token is a shared secret that agents use to authenticate with the server API.

- Auto-generated during server install if `K3S_NODE_TOKEN` is empty
- Automatically read from the server by the Ansible `site.yml` playbook
- Stored on the server at `/var/lib/rancher/k3s/server/node-token`

To rotate: uninstall both nodes and reinstall with a new token.

---

## Datastore backup

A single server keeps all cluster state in SQLite
(`/var/lib/rancher/k3s/server/db/state.db`). The `k3s_server` role installs a
daily `k3s-db-backup.timer` that writes
`/var/backups/k3s/k3s-<UTC timestamp>.tar.gz` (mode 0600, newest 7 kept). Each
archive holds:

| File | Why it is needed |
| ---- | ---------------- |
| `state.db` | the cluster state, snapshotted online |
| `token` | k3s refuses to start on a datastore with a different server token |
| `encryption-config.json` | Secrets are encrypted at rest (`--secrets-encryption`) — unreadable without it |

Tune with `k3s_db_backup_*` in `group_vars` (`k3s_db_backup_enabled: false` to
turn it off). **Copy the archives off the node** from your own config repo
(restic, rclone, …): a backup on the same disk does not survive that disk.

Restore on a server with the same k3s version:

```bash
systemctl stop k3s
mkdir -p /tmp/k3s-restore && tar -C /tmp/k3s-restore -xzf k3s-<stamp>.tar.gz
cp /tmp/k3s-restore/state.db               /var/lib/rancher/k3s/server/db/state.db
cp /tmp/k3s-restore/token                  /var/lib/rancher/k3s/server/token
cp /tmp/k3s-restore/encryption-config.json /var/lib/rancher/k3s/server/cred/
rm -f /var/lib/rancher/k3s/server/db/state.db-{wal,shm}
systemctl start k3s
```

PersistentVolume data (`local-path`) is **not** in this archive — back up
volumes separately (e.g. Velero) from your config repo.

---

## References

- [k3s documentation](https://docs.k3s.io)
- [k3s installation requirements](https://docs.k3s.io/installation/requirements)
- [k3s configuration reference](https://docs.k3s.io/installation/configuration)
- [Flannel networking](https://docs.k3s.io/networking/basic-network-options)
