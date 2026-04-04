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
│          Server (VPS 1)         │    │          Agent (VPS 2)          │
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
| 2 vCPU / 2 GB RAM (server) | 1 GB minimum for agent |
| Public IP on each VPS | Required for TLS SAN + UFW rules |
| SSH access as root or sudo user | Bootstrap uses `INITIAL_USER=root` |
| Port `6443` open on server | k3s API server |
| Ports `80`, `443` open on server | HTTP + HTTPS traffic |

---

## Install flags explained

The server install script (`k3s/install-server.sh`) uses these key flags:

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

### Server node

| Port | Protocol | Purpose |
|---|---|---|
| `80` | TCP | HTTP (Traefik + ACME HTTP-01 challenge) |
| `443` | TCP | HTTPS (Traefik TLS termination) |
| `6443` | TCP | Kubernetes API server |
| `10.42.0.0/16` | any | k3s pod CIDR (Flannel) |
| `10.43.0.0/16` | any | k3s service CIDR |
| `8472` from AGENT_IP | UDP | Flannel VXLAN tunnel |
| `10250` from AGENT_IP | TCP | kubelet API |

### Agent node

| Port | Protocol | Purpose |
|---|---|---|
| `8472` from SERVER_IP | UDP | Flannel VXLAN tunnel |
| `10250` from SERVER_IP | TCP | kubelet API |

---

## Installation workflow

### 1. Bootstrap server

```bash
make k3s-server
```

This:
1. Copies `k3s/install-server.sh` to the VPS over SCP
2. Runs the script as root via SSH
3. Waits for the node to be `Ready`
4. Reads the node token and saves it to `.env` as `K3S_NODE_TOKEN`

### 2. Bootstrap agent

```bash
make k3s-agent
```

This:
1. Opens the server UFW firewall for the agent IP
2. Copies `k3s/install-agent.sh` to the agent VPS
3. Runs the script with `K3S_TOKEN` and `SERVER_IP`

### 3. Fetch kubeconfig

```bash
make kubeconfig
```

Fetches `/etc/rancher/k3s/k3s.yaml` from the server, replaces `127.0.0.1` with the public IP, and merges it into `~/.kube/config` under the context name `KUBECONFIG_CONTEXT`.

---

## Uninstall

```bash
make k3s-uninstall-server   # Remove k3s from server (DESTRUCTIVE)
make k3s-uninstall-agent    # Remove k3s from agent (DESTRUCTIVE)
```

The uninstall script (`k3s/uninstall.sh`):
- Runs the official `k3s-uninstall.sh` or `k3s-agent-uninstall.sh`
- Cleans up CNI interfaces (`flannel.1`, `cni0`)
- Flushes iptables rules
- Unmounts k3s bind mounts

---

## Node token

The node token is a shared secret that agents use to authenticate with the server API.

- Auto-generated during server install if `K3S_NODE_TOKEN` is empty
- Automatically saved to `.env` by `make k3s-server`
- Stored on the server at `/var/lib/rancher/k3s/server/node-token`

To rotate: uninstall both nodes and reinstall with a new token.

---

## References

- [k3s documentation](https://docs.k3s.io)
- [k3s installation requirements](https://docs.k3s.io/installation/requirements)
- [k3s configuration reference](https://docs.k3s.io/installation/configuration)
- [Flannel networking](https://docs.k3s.io/networking/basic-network-options)
