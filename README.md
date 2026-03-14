# k3s-lab

> Production-ready k3s cluster on VPS — automated setup with Traefik, cert-manager, Prometheus, Grafana, Loki, and Promtail.

[![CI / CD](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci-cd.yml)

## Stack

| Tool | Role |
|---|---|
| [k3s](https://k3s.io) | Lightweight Kubernetes distribution |
| [Traefik](https://traefik.io) | Ingress controller + HTTPS |
| [cert-manager](https://cert-manager.io) | Automatic TLS via Let's Encrypt |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) | Prometheus + Grafana + Alertmanager |
| [Loki](https://grafana.com/oss/loki/) | Centralized log storage |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Log collector |

## Quick start

```bash
cp .env.example .env        # Fill in your values
make k3s-master             # Bootstrap control plane (~5 min)
make k3s-worker             # Join worker node (~3 min)
make kubeconfig             # Fetch kubeconfig
make deploy-dashboard-secret
make deploy                 # Traefik + cert-manager (~3 min)
make deploy-grafana-secret
make deploy-monitoring      # Prometheus + Grafana + Loki (~10 min)
```

## Documentation

📖 **[kevindebenedetti.github.io/k3s-lab](https://kevindebenedetti.github.io/k3s-lab)**

| | |
|---|---|
| [Getting started](https://kevindebenedetti.github.io/k3s-lab/getting-started) | Prerequisites, step-by-step deploy |
| [Configuration](https://kevindebenedetti.github.io/k3s-lab/configuration) | All `.env` variables |
| [k3s](https://kevindebenedetti.github.io/k3s-lab/stack/k3s) | Install flags, sysctl, firewall |
| [Traefik](https://kevindebenedetti.github.io/k3s-lab/stack/traefik) | Ingress, TLS, dashboard |
| [cert-manager](https://kevindebenedetti.github.io/k3s-lab/stack/cert-manager) | Let's Encrypt, HTTP-01 |
| [Monitoring](https://kevindebenedetti.github.io/k3s-lab/stack/monitoring) | Prometheus, Grafana, Loki |
| [Make targets](https://kevindebenedetti.github.io/k3s-lab/operations/make-targets) | Full `make` reference |
| [Troubleshooting](https://kevindebenedetti.github.io/k3s-lab/operations/troubleshooting) | Common issues |

## Submodule usage

```bash
git submodule add https://github.com/KevinDeBenedetti/k3s-lab.git k3s-lab
```

```makefile
K3S_LAB := $(ROOT_DIR)/k3s-lab
include $(K3S_LAB)/makefiles/30-k3s.mk
include $(K3S_LAB)/makefiles/40-kubeconfig.mk
include $(K3S_LAB)/makefiles/50-deploy.mk
include $(K3S_LAB)/makefiles/60-status.mk
include $(K3S_LAB)/makefiles/70-ssh.mk
```
