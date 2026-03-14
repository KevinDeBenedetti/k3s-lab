# k3s-lab

> Production-ready k3s cluster on VPS — automated setup with Traefik, cert-manager, Prometheus, Grafana, Loki, and Promtail.

## Stack

| Tool                                                                         | Role                                |
| ---------------------------------------------------------------------------- | ----------------------------------- |
| [k3s](https://k3s.io)                                                        | Lightweight Kubernetes distribution |
| [Traefik](https://traefik.io)                                                | Ingress controller + HTTPS          |
| [cert-manager](https://cert-manager.io)                                      | Automatic TLS via Let's Encrypt     |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) | Prometheus + Grafana + Alertmanager |
| [Loki](https://grafana.com/oss/loki/)                                        | Centralized log storage             |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/)         | Log collector (DaemonSet)           |

## Architecture

```
Internet
    │
    ▼
Traefik (master :80/:443)
    │
    ├─► Traefik dashboard   (dashboard.DOMAIN)
    ├─► Grafana             (grafana.DOMAIN)
    └─► Your apps           (app.DOMAIN)

Prometheus ◄── Scrapes all namespaces (ServiceMonitor)
Loki       ◄── Promtail DaemonSet (all nodes)
```

## Quick start

```bash
# 1. Configure environment
cp .env.example .env
# Fill in MASTER_IP, WORKER_IP, DOMAIN, EMAIL, etc.

# 2. Bootstrap k3s cluster
make k3s-master      # ~5 min — also saves K3S_NODE_TOKEN to .env
make k3s-worker      # ~3 min

# 3. Fetch kubeconfig
make kubeconfig
kubectl config use-context k3s-lab

# 4. Deploy base stack (Traefik + cert-manager)
make deploy-dashboard-secret
make deploy          # ~3 min

# 5. Deploy monitoring (Prometheus + Grafana + Loki)
make deploy-grafana-secret
make deploy-monitoring   # ~10 min
```

## Documentation

📖 **[kevindebenedetti.github.io/k3s-lab](https://kevindebenedetti.github.io/k3s-lab)**

| Section                                                                                  | Description                                 |
| ---------------------------------------------------------------------------------------- | ------------------------------------------- |
| [Getting started](https://kevindebenedetti.github.io/k3s-lab/getting-started)            | Prerequisites and step-by-step first deploy |
| [Configuration](https://kevindebenedetti.github.io/k3s-lab/configuration)                | All `.env` variables explained              |
| [k3s](https://kevindebenedetti.github.io/k3s-lab/stack/k3s)                              | k3s install flags, sysctl, firewall         |
| [Traefik](https://kevindebenedetti.github.io/k3s-lab/stack/traefik)                      | Ingress, TLS, dashboard, middlewares        |
| [cert-manager](https://kevindebenedetti.github.io/k3s-lab/stack/cert-manager)            | Let's Encrypt, ClusterIssuers, HTTP-01      |
| [Monitoring](https://kevindebenedetti.github.io/k3s-lab/stack/monitoring)                | Prometheus, Grafana, Loki, Promtail         |
| [Make targets](https://kevindebenedetti.github.io/k3s-lab/operations/make-targets)       | Full `make` reference                       |
| [Local testing](https://kevindebenedetti.github.io/k3s-lab/operations/local-testing)     | BATS tests + Lima VM local k3s cluster      |
| [Troubleshooting](https://kevindebenedetti.github.io/k3s-lab/operations/troubleshooting) | Common issues and fixes                     |

## Repository layout

```
.
├── .env.example             # Environment template — copy to .env
├── k3s/                     # Bootstrap scripts (run remotely on VPS)
│   ├── install-master.sh    # Control plane setup
│   ├── install-worker.sh    # Worker node join
│   └── uninstall.sh         # Remove k3s from a node
├── kubernetes/              # Kubernetes manifests
│   ├── namespaces/          # Namespace definitions
│   ├── ingress/             # Traefik Helm values + dashboard
│   ├── cert-manager/        # Let's Encrypt ClusterIssuers
│   ├── monitoring/          # Prometheus, Grafana, Loki, Promtail
│   └── apps/                # Example app deployment
├── scripts/                 # Local deploy scripts
├── makefiles/               # Modular Makefile targets
├── lib/                     # Shared shell helpers
├── tests/                   # BATS unit tests
└── docs/                    # Full documentation
```

## CI

[![CI / CD](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci-cd.yml)

- **shellcheck** — all shell scripts at warning severity
- **actionlint** — GitHub Actions workflows
- **kubeconform** — Kubernetes manifest schema validation
- **bats** — offline unit tests
- **gitleaks** — secret scanning

## Usage as a submodule

```bash
git submodule add https://github.com/KevinDeBenedetti/k3s-lab.git k3s-lab
```

In your parent `Makefile`:

```makefile
K3S_LAB := $(ROOT_DIR)/k3s-lab

include $(K3S_LAB)/makefiles/30-k3s.mk
include $(K3S_LAB)/makefiles/40-kubeconfig.mk
include $(K3S_LAB)/makefiles/50-deploy.mk
include $(K3S_LAB)/makefiles/60-status.mk
include $(K3S_LAB)/makefiles/70-ssh.mk
```
