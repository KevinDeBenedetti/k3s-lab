# k3s-homelab

> Reusable k3s cluster setup — scripts, Kubernetes manifests, and Makefile targets for a production-ready lightweight Kubernetes cluster on VPS nodes.

## Stack

| Tool | Role |
|------|------|
| [k3s](https://k3s.io) | Lightweight Kubernetes distribution |
| [Traefik](https://traefik.io) | Ingress controller + HTTPS reverse proxy |
| [cert-manager](https://cert-manager.io) | Automatic TLS via Let's Encrypt |
| [Loki](https://grafana.com/oss/loki/) | Centralized log storage |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Kubernetes log collector |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) | Prometheus + Grafana monitoring |

## Repository Layout

```
.
├── .env.example             # Environment variables template — copy to .env
├── k3s/
│   ├── install-master.sh    # Bootstrap the control-plane node
│   ├── install-worker.sh    # Join a worker node to the cluster
│   └── uninstall.sh         # Remove k3s from a node
├── kubernetes/
│   ├── namespaces/          # apps, ingress, cert-manager, monitoring
│   ├── ingress/             # Traefik Helm values + secured dashboard
│   ├── cert-manager/        # Let's Encrypt ClusterIssuers
│   ├── monitoring/          # Prometheus, Grafana, Loki, Promtail
│   └── apps/                # Example app deployment + ingress
├── lib/
│   ├── load-env.sh          # .env loader (no-overwrite semantics)
│   ├── log.sh               # Coloured logging helpers
│   └── ssh-opts.sh          # SSH_OPTS array builder
├── makefiles/               # Modular Makefile targets
│   ├── 10-help.mk           # Auto-generated help
│   ├── 30-k3s.mk            # k3s install / uninstall
│   ├── 40-kubeconfig.mk     # Fetch & merge kubeconfig
│   ├── 50-deploy.mk         # Deploy base + monitoring stack
│   ├── 60-status.mk         # Cluster status helpers
│   └── 70-ssh.mk            # SSH shortcuts
└── scripts/
    ├── deploy-stack.sh      # Deploy Traefik + cert-manager (local machine)
    ├── deploy-monitoring.sh # Deploy Prometheus + Grafana + Loki + Promtail
    └── get-kubeconfig.sh    # Fetch & merge kubeconfig from master
```

## Quick Start

```bash
# 1. Copy and fill in your values
cp .env.example .env

# 2. Install k3s on the master node
make k3s-master

# 3. Fetch kubeconfig
make kubeconfig

# 4. Deploy the base stack (Traefik + cert-manager)
make deploy

# 5. Deploy monitoring (Prometheus + Grafana + Loki)
make deploy-monitoring
```

## Available Targets

```
make help
```

## Usage as a Git Submodule

This repo is designed to be embedded in a private infra repo:

```bash
git submodule add git@github.com:KevinDeBenedetti/k3s-homelab.git k3s-homelab
```

In the parent `Makefile`:

```makefile
K3S_HOMELAB := $(ROOT_DIR)/k3s-homelab
include $(K3S_HOMELAB)/makefiles/30-k3s.mk
include $(K3S_HOMELAB)/makefiles/40-kubeconfig.mk
include $(K3S_HOMELAB)/makefiles/50-deploy.mk
include $(K3S_HOMELAB)/makefiles/60-status.mk
include $(K3S_HOMELAB)/makefiles/70-ssh.mk
```

## Environment Variables

See [.env.example](.env.example) for the full list. Key variables:

| Variable | Description |
|----------|-------------|
| `MASTER_IP` | Public IP of the master VPS |
| `WORKER_IP` | Public IP of the worker VPS |
| `SSH_USER` | SSH user (default: `kevin`) |
| `SSH_KEY` | Path to SSH private key |
| `K3S_VERSION` | Pinned k3s version |
| `DOMAIN` | Primary domain (e.g. `example.com`) |
| `EMAIL` | Let's Encrypt registration email |
| `GRAFANA_DOMAIN` | Grafana dashboard domain |
| `KUBECONFIG_CONTEXT` | kubectl context name |
