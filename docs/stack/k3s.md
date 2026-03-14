# k3s — Lightweight Kubernetes

[k3s](https://k3s.io) is a certified, production-ready Kubernetes distribution packaged as a single binary (~100 MB). It is optimized for VPS, edge, and IoT environments.

## Why k3s

| Feature | Value |
|---|---|
| Single binary | No Docker daemon required |
| Built-in containerd | Reduced resource footprint |
| ARM + x86 support | Works on any VPS |
| Certified Kubernetes | 100% API compatible |
| Automatic TLS | Internal cluster PKI included |

---

## Architecture

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│          Master (VPS 1)         │    │          Worker (VPS 2)         │
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

| Requirement | Notes |
|---|---|
| Ubuntu 22.04+ / Debian 12+ | Both nodes |
| 2 vCPU / 2 GB RAM (master) | 1 GB minimum for agent |
| Public IP on each VPS | Required for TLS SAN + UFW rules |
| SSH access as root or sudo user | Bootstrap uses `INITIAL_USER=root` |
| Port `6443` open on master | k3s API server |
| Ports `80`, `443` open on master | HTTP + HTTPS traffic |

---

## Install flags explained

The master install script (`k3s/install-master.sh`) uses these key flags:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_TOKEN="${K3S_NODE_TOKEN}" \
  sh -s - server \
    --disable=traefik \          # Managed via Helm for full control
    --disable=servicelb \        # No built-in LB — use externalIPs instead
    --node-ip="${NODE_IP}" \     # Internal NIC IP (Flannel overlay)
    --advertise-address="${NODE_IP}" \
    --tls-san="${PUBLIC_IP}" \   # Public IP added to API server certificate SAN
    --flannel-backend=vxlan \    # Stable VXLAN overlay (UDP 8472)
    --protect-kernel-defaults \  # Enforces sysctl requirements
    --secrets-encryption \       # Encrypts Kubernetes Secrets at rest
    --write-kubeconfig-mode=600  # Restrict kubeconfig permissions
```

> **`--tls-san`** is critical — without the public IP in the TLS SAN, your local `kubectl` will get a certificate error when connecting remotely.

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

### Master node

| Port | Protocol | Purpose |
|---|---|---|
| `80` | TCP | HTTP (Traefik + ACME HTTP-01 challenge) |
| `443` | TCP | HTTPS (Traefik TLS termination) |
| `6443` | TCP | Kubernetes API server |
| `10.42.0.0/16` | any | k3s pod CIDR (Flannel) |
| `10.43.0.0/16` | any | k3s service CIDR |
| `8472` from WORKER_IP | UDP | Flannel VXLAN tunnel |
| `10250` from WORKER_IP | TCP | kubelet API |

### Worker node

| Port | Protocol | Purpose |
|---|---|---|
| `8472` from MASTER_IP | UDP | Flannel VXLAN tunnel |
| `10250` from MASTER_IP | TCP | kubelet API |

---

## Installation workflow

### 1. Bootstrap master

```bash
make k3s-master
```

This:
1. Copies `k3s/install-master.sh` to the VPS over SCP
2. Runs the script as root via SSH
3. Waits for the node to be `Ready`
4. Reads the node token and saves it to `.env` as `K3S_NODE_TOKEN`

### 2. Bootstrap worker

```bash
make k3s-worker
```

This:
1. Opens the master UFW firewall for the worker IP
2. Copies `k3s/install-worker.sh` to the worker VPS
3. Runs the script with `K3S_TOKEN` and `MASTER_IP`

### 3. Fetch kubeconfig

```bash
make kubeconfig
```

Fetches `/etc/rancher/k3s/k3s.yaml` from the master, replaces `127.0.0.1` with the public IP, and merges it into `~/.kube/config` under the context name `KUBECONFIG_CONTEXT`.

---

## Uninstall

```bash
make k3s-uninstall-master   # Remove k3s from master (DESTRUCTIVE)
make k3s-uninstall-worker   # Remove k3s from worker (DESTRUCTIVE)
```

The uninstall script (`k3s/uninstall.sh`):
- Runs the official `k3s-uninstall.sh` or `k3s-agent-uninstall.sh`
- Cleans up CNI interfaces (`flannel.1`, `cni0`)
- Flushes iptables rules
- Unmounts k3s bind mounts

---

## Node token

The node token is a shared secret that workers use to authenticate with the master API.

- Auto-generated during master install if `K3S_NODE_TOKEN` is empty
- Automatically saved to `.env` by `make k3s-master`
- Stored on the master at `/var/lib/rancher/k3s/server/node-token`

To rotate: uninstall both nodes and reinstall with a new token.

---

## References

- [k3s documentation](https://docs.k3s.io)
- [k3s installation requirements](https://docs.k3s.io/installation/requirements)
- [k3s configuration reference](https://docs.k3s.io/installation/configuration)
- [Flannel networking](https://docs.k3s.io/networking/basic-network-options)
